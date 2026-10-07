const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/\binit\(\);\s*$/, '');
function app() {
  const items = new Map();
  const messages = [];
  const element = { classList: { remove() {}, add() {} }, style: {}, addEventListener() {} };
  const ctx = vm.createContext({ console, Date, Intl, setTimeout: () => 0, clearTimeout() {},
    setInterval() {}, navigator: { userAgent: '' }, location: { protocol: 'file:' },
    window: { addEventListener() {}, crewclock: { postMessage: s => messages.push(JSON.parse(s)) } },
    document: { addEventListener() {}, getElementById: () => element }, confirm: () => true,
    localStorage: { getItem: k => items.get(k) ?? null, setItem: (k, v) => items.set(k, v), removeItem: k => items.delete(k) }
  });
  vm.runInContext(script, ctx);
  for (const name of ['renderDirectAlarms', 'renderCal', 'renderDaySchedule', 'renderHomeFlightList', 'toast', 'stopSnd', 'releaseWakeLock']) ctx[name] = () => {};
  return { ctx, items, messages };
}
test('ICS import opens the picker and closes the sheet without the legacy step', () => {
  const { ctx } = app();
  const calls = [];
  ctx.setImportMode = () => assert.fail('Legacy ICS step must not open');
  ctx.chooseICSFile = () => calls.push('picker');
  ctx.closeUploadSheet = () => calls.push('close');
  ctx.openICSImport();
  assert.deepEqual(calls, ['picker', 'close']);
});
test('native DB arrays and legacy JSON strings both restore alarms', () => {
  const { ctx, items } = app();
  const alarms = [{ id: 'test', time: '2030-01-01T00:00:00Z', type: 'direct', armed: 1, dism: 0 }];
  ctx.syncAlarmsFromDB(alarms);
  assert.equal(ctx.alms.length, 1);
  assert.equal(ctx.alms[0].armed, true);
  assert.equal(JSON.parse(items.get('crewclock_alarms')).length, 1);
  ctx.syncAlarmsFromDB(JSON.stringify(alarms));
  assert.equal(ctx.alms.length, 1);
});
test('deleting flights and alarms sends an empty native schedule and stop command', () => {
  const { ctx, messages } = app();
  ctx.alms = [{ id: 'test', time: new Date('2030-01-01'), type: 'direct' }];
  ctx.clearAllData();
  assert.ok(messages.some(m => Array.isArray(m) && m.length === 0));
  assert.ok(messages.some(m => m.type === 'STOP_RINGING_ALARM'));
});
test('notification Stop closes the ringing popup when native dismissal is synced', () => {
  const { ctx } = app();
  const removed = [];
  let stopped = 0;
  ctx.document.getElementById = () => ({ _alarmID: 'stopped', classList: { remove: name => removed.push(name) } });
  ctx.stopSnd = () => stopped++;
  ctx.alms = [{ id: 'stopped', ring: false }];
  ctx.syncAlarmsFromDB([{ id: 'stopped', time: '2030-01-01T00:00:00Z', type: 'direct', armed: 1, dism: 1 }]);
  assert.equal(stopped, 1);
  assert.ok(removed.includes('show'));
  assert.equal(ctx.alms[0].dism, true);
});
test('foreground alarms ring for two minutes and pause for five, until dismissed', () => {
  const { ctx } = app();
  const RealDate = Date;
  const base = RealDate.parse('2030-10-07T12:00:00Z');
  let now = base;
  ctx.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [now])); }
  };
  let rings = 0, pauses = 0;
  ctx.trigAlarm = () => rings++;
  ctx.checkAndStopGlobalAlarm = () => pauses++;
  ctx.todayStr = () => '2030-10-07';
  const alarm = { id: 'cycle', type: 'direct', time: new ctx.Date(base), armed: true };
  ctx.alms = [alarm];
  for (const offset of [0, 119999, 120000, 419999, 420000, 539999, 540000]) {
    now = base + offset;
    ctx.checkAlarms();
    assert.equal(alarm.ring, offset % 420000 < 120000);
  }
  assert.equal(rings, 2);
  assert.equal(pauses, 2);
  alarm.dism = true;
  now = base + 840000;
  ctx.checkAlarms();
  assert.equal(rings, 2);
  alarm.dism = false;
  ctx.window.crewclockSystemAlarm = true;
  ctx.checkAlarms();
  assert.equal(rings, 2, 'native alarms must not ring again in the WebView');
});
test('IANA time zones honor winter and summer UTC offsets', () => {
  const { ctx } = app();
  assert.equal(ctx.parseICSDate('20300115T090000', 'America/New_York').toISOString(), '2030-01-15T14:00:00.000Z');
  assert.equal(ctx.parseICSDate('20300715T090000', 'America/New_York').toISOString(), '2030-07-15T13:00:00.000Z');
  assert.equal(ctx.parseICSDate('20300715T090000Z').toISOString(), '2030-07-15T09:00:00.000Z');
});
test('invalid and ambiguous daylight-saving times are rejected', () => {
  const { ctx } = app();
  assert.throws(() => ctx.parseICSDate('20300310T023000', 'America/New_York'), /nonexistent/);
  assert.throws(() => ctx.parseICSDate('20301103T013000', 'America/New_York'), /ambiguous/);
  assert.throws(() => ctx.parseICSDate('20300101T090000', 'Invalid/Zone'));
});
test('flight import retains absolute time and accepts alphanumeric airline codes', () => {
  const { ctx } = app();
  const flights = ctx.parseICS('BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART;TZID=America/New_York:20300715T090000\nDTEND;TZID=America/Los_Angeles:20300715T120000\nSUMMARY:B6 1 JFK-LAX\nEND:VEVENT\nEND:VCALENDAR');
  assert.equal(flights.length, 1);
  assert.equal(flights[0].flight, 'B61');
  assert.equal(flights[0].departureUtc, '2030-07-15T13:00:00.000Z');
  assert.equal(ctx.parseFlightDate(flights[0]).toISOString(), '2030-07-15T13:00:00.000Z');
});
test('DOH flights are not excluded as DO duty codes', () => {
  const { ctx } = app();
  const flights = ctx.parseICS('BEGIN:VEVENT\nDTSTART:20300715T000000Z\nDTEND:20300715T060000Z\nSUMMARY:QR1 DOH-LHR\nEND:VEVENT');
  assert.equal(flights.length, 1);
  assert.equal(flights[0].depApt, 'DOH');
  assert.equal(flights[0].isArrivalOnly, false);
});

test('travel refreshes displayed dates without changing the departure instant', () => {
  const { ctx } = app();
  const flight = { date: '1999-01-01', depTime: '00:00', departureUtc: '2030-07-15T13:00:00Z', arrivalUtc: '2030-07-15T19:00:00Z' };
  ctx.refreshFlightLocalTimes(flight);
  assert.equal(flight.depTime, ctx.fmt(new Date(flight.departureUtc)));
  assert.equal(flight.arrTime, ctx.fmt(new Date(flight.arrivalUtc)));
  assert.notEqual(flight.date, '1999-01-01');
  assert.equal(ctx.parseFlightDate(flight).toISOString(), '2030-07-15T13:00:00.000Z');
});

test('recurring flight events fail clearly instead of importing only one occurrence', () => {
  const { ctx } = app();
  assert.throws(() => ctx.parseICS('BEGIN:VEVENT\nDTSTART:20300715T090000Z\nSUMMARY:BA1 LHR-JFK\nRRULE:FREQ=DAILY;COUNT=3\nEND:VEVENT'), /Recurring flight events/);
});

test('manual pasted iPhone schedule text parses dates, arrows, and airline codes', () => {
  const { ctx } = app();
  const els = new Map([
    ['manualFlightInput', { value: 'Mon 03 Jun 2025  KE913  ICN → MAD  09:55–17:45' }],
    ['manualMonth', { value: '2025-06' }],
  ]);
  ctx.document.getElementById = id => els.get(id) || { value: '', focus(){}, scrollIntoView(){}, classList: { add(){}, remove(){} }, style:{} };
  ctx.closeUploadSheet=()=>{};
  ctx.replaceMonthFlights = flights => { ctx.__flights = flights; return flights.length; };
  ctx.initFlightToggles = ctx.autoRegisterAll = ctx.saveFlights = ctx.renderHomeFlightList = ctx.renderSheetFalWrap = ctx.renderCal = ctx.renderDaySchedule = () => {};
  ctx.parseManualEntry();
  assert.equal(ctx.__flights, undefined, 'review must not write schedules');
  ctx.confirmManualImport();
  assert.equal(ctx.__flights.length, 1);
  assert.equal(ctx.__flights[0].flight, 'KE913');
  assert.equal(ctx.__flights[0].date, '2025-06-03');
  assert.equal(ctx.__flights[0].depApt, 'ICN');
  assert.equal(ctx.__flights[0].arrApt, 'MAD');
});

test('monthly roster joins next-day arrivals and preserves same-day date-line crossings', () => {
  const {ctx}=app();
  const result=ctx.parseManualSchedule('October 2030\nSunday\nOct 03\nKE 901 ICN 13:40 - IST 19:40\nLO IST\nOct 04\nKE 902 IST 21:20 - ICN\nOct 05\nKE 902 IST - ICN 13:25\nOct 17\nKE 031 ICN 09:20 - DFW 08:10\nOct 30\n787UPRT ICN 15:50 - ICN 22:30','2029-11');
  assert.equal(result.errors.length,0);
  assert.equal(result.flights.length,3);
  assert.equal(result.flights[0].date,'2030-10-03');
  assert.equal(result.flights[1].arrDate,'2030-10-05');
  assert.equal(result.flights[1].depTime,'21:20');
  assert.equal(result.flights[2].arrDate,'2030-10-17');
});

test('OCR airport corrections are reported and ambiguous codes block registration',()=>{
  const {ctx}=app();
  const result=ctx.parseManualSchedule('Oct 08\nKE 433 IN 18:00 - DPS 23:50\nOct 10\nKE 434 DPS 01:10 - ICN 09:25ł\nOct 25\nDH 678 HKT 22:55 - IC\nOct 26\nDH 678 HKT - ICN 06:40','2030-10');
  assert.equal(result.errors.length,0);
  assert.equal(result.flights.length,3);
  assert.equal(result.flights[0].depApt,'ICN');
  assert.equal(result.flights[2].flight,'DH678');
  assert.ok(!result.warnings.some(w=>w.includes('flight number')), 'DH is an extra assignment, not a typo');
  assert.equal(result.flights[2].arrDate,'2030-10-26');
  assert.ok(result.warnings.some(w=>w.includes('IN → ICN')));
  assert.ok(result.warnings.some(w=>w.includes('IC → ICN')));
  const ambiguous=ctx.parseManualSchedule('Oct 08\nKE 433 IN 18:00 - DPS 23:50\nOct 09\nKE 434 DPS 01:10 - ICN 09:25\nKE 435 INN 12:00 - DPS 13:00','2030-10');
  assert.ok(ambiguous.errors.some(e=>e.includes('incomplete')));
});

test('invalid dates, missing dates, bad times and orphan arrivals do not silently import',()=>{
  const {ctx}=app();
  for(const raw of ['Oct 32\nKE 433 ICN 18:00 - DPS 23:50','KE 433 ICN 18:00 - DPS 23:50','Oct 08\nKE 433 ICN 25:00 - DPS 23:50','Oct 09\nKE 434 DPS - ICN 09:25','Oct 08\nKE 433 ICN 18:00 - DPS']){
    assert.ok(ctx.parseManualSchedule(raw,'2030-10').errors.length>0,raw);
  }
});

test('numbered dates, compact times, alphanumeric airlines and repeated pastes are supported',()=>{
  const {ctx}=app();
  const line='03 B6 1 JFK 0900 LAX 1200';
  const result=ctx.parseManualSchedule(line+'\n'+line,'2030-10');
  assert.equal(result.errors.length,0);
  assert.equal(result.flights.length,1);
  assert.equal(result.flights[0].flight,'B61');
  assert.equal(result.flights[0].depTime,'09:00');
});

test('a roster without its month/year title uses the selected year and individual date headings',()=>{
  const {ctx}=app();
  const result=ctx.parseManualSchedule('Sunday\nMonday\nOct 25\nDH 678 HKT 22:55 - ICN\nOct 26\nDH 678 HKT - ICN 06:40','2031-09');
  assert.equal(result.errors.length,0);
  assert.equal(result.flights[0].date,'2031-10-25');
  assert.equal(result.flights[0].arrDate,'2031-10-26');
  assert.equal(result.flights[0].flight,'DH678');
});

test('calendar columns copied out of date order still join departure and arrival',()=>{
  const {ctx}=app();
  const result=ctx.parseManualSchedule('Oct 05\nKE 956 IST - ICN 13:25\nOct 04\nKE 956 IST 21:20 - ICN','2030-10');
  assert.equal(result.errors.length,0);
  assert.equal(result.flights.length,1);
  assert.equal(result.flights[0].date,'2030-10-04');
  assert.equal(result.flights[0].arrDate,'2030-10-05');
});

test('DH extra assignments register the same enabled reminders as operating flights',()=>{
  function register(prefix,disableCheckout){
    const {ctx,messages}=app();
    ctx.document.getElementById=()=>null;
    ctx.todayStr=()=>'2030-10-01';
    ctx.resetDef();
    if(disableCheckout)ctx.intlOn.i2=false;
    const parsed=ctx.parseManualSchedule('Oct 25\n'+prefix+' 678 HKT 22:55 - ICN\nOct 26\n'+prefix+' 678 HKT - ICN 06:40','2030-10');
    assert.equal(parsed.errors.length,0);
    ctx.detectedFlights=parsed.flights;
    ctx.initFlightToggles();
    ctx.autoRegisterAll();
    const alarms=JSON.parse(JSON.stringify(ctx.alms));
    assert.ok(alarms.every(a=>a.fnum===prefix+'678'&&a.armed));
    assert.equal(messages.at(-1).length,alarms.length,'all reminders reach the native bridge');
    ctx.autoRegisterAll();
    assert.equal(ctx.alms.length,alarms.length,'no duplicate alarms when registered again');
    return alarms.map(a=>({time:a.time,label:a.lbl,type:a.type,depApt:a.depApt,arrApt:a.arrApt}));
  }
  const dh=register('DH',false);
  assert.equal(dh.length,3);
  assert.deepEqual(dh,register('KE',false));
  assert.deepEqual(dh.map(a=>{const d=new Date(a.time);return d.getHours()+':'+String(d.getMinutes()).padStart(2,'0');}),['19:55','20:55','22:15']);
  const reduced=register('DH',true);
  assert.equal(reduced.length,2);
  assert.deepEqual(reduced,register('KE',true));
});
