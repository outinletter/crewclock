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
test('departure-local alarm dates and times remain fixed after arrival in Korea',()=>{
  const {ctx}=app();let now=Date.parse('2026-10-19T12:00:00Z');
  ctx.Date=class extends Date{constructor(...args){super(...(args.length?args:[now]));}static now(){return now;}};
  ctx.detectedFlights=ctx.parseICS('BEGIN:VEVENT\nDTSTART:20261017T002000Z\nDTEND:20261017T131000Z\nSUMMARY:KE031 ICN-DFW\nEND:VEVENT\nBEGIN:VEVENT\nDTSTART:20261019T165500Z\nDTEND:20261020T060000Z\nSUMMARY:KE032 DFW-ICN\nEND:VEVENT');
  const f=ctx.detectedFlights[1],dep=ctx.parseFlightDate(f),a={id:'old-import',type:'intl',fnum:f.flight,depApt:'DFW',dep,time:new ctx.Date(+dep-3*3600000)};
  assert.equal(ctx.appZone(),'America/Chicago');assert.equal(ctx.alarmTimeText(a,a.time),'08:55');
  now=Date.parse('2026-10-20T07:00:00Z');
  assert.equal(ctx.appZone(),'Asia/Seoul');assert.equal(ctx.fmt(dep),'01:55');
  assert.equal(ctx.alarmDepDay(a),'2026-10-19');assert.equal(ctx.alarmTimeText(a,dep),'11:55');
  assert.equal(ctx.alarmTimeText(a,a.time),'08:55');assert.equal(a.time.toISOString(),'2026-10-19T13:55:00.000Z');
  assert.equal(ctx.findFlightForAlarm(a),f,'reimported flight IDs still match the departure-local date');
  ctx.resetDef();ctx.detectedFlights=[f];ctx.alms=[a];
  assert.ok(ctx.buildDisplayedDayAlarms('2026-10-19',[f]).some(row=>row.id===a.id));
  assert.equal(ctx.buildDisplayedDayAlarms('2026-10-20',[]).length,0);
});
test('personal preparation persists per departure, survives reimport and stays separate from alarms',()=>{
  const {ctx,items,messages}=app();ctx.document.getElementById=()=>null;
  const f={id:'one',flight:'CC102',depApt:'DFW',arrApt:'ICN',departureUtc:'2030-07-19T16:55:00Z',type:'intl'};
  ctx.detectedFlights=[f];ctx.toggleBriefingTask(0);ctx.saveBriefingNote('Hotel pickup 08:20');
  assert.ok(ctx.briefingState(f).tasks[0].checkedAt);assert.equal(ctx.briefingState(f).note,'Hotel pickup 08:20');
  assert.equal(ctx.briefingState({...f,id:'reimported'}).note,'Hotel pickup 08:20');
  assert.equal(ctx.briefingState({...f,departureUtc:'2030-07-20T16:55:00Z'}).note,'');
  assert.ok(items.has('crewclock_briefings_v1'));assert.equal(messages.length,0);assert.equal(ctx.alms.length,0);
  ctx.toggleBriefingTask(0);assert.equal(ctx.briefingState(f).tasks[0].checkedAt,null);
});
test('briefing demo and PDF export do not import or register fictional alarms',()=>{
  const {ctx,items,messages}=app();ctx.document.getElementById=()=>null;ctx.resetDef();
  ctx.startBriefingDemo();ctx.toggleBriefingTask(1);ctx.saveBriefingNote('Pickup lobby');ctx.exportDutyBriefing();
  assert.equal(ctx.detectedFlights.length,0);assert.equal(ctx.alms.length,0);assert.equal(items.size,0);
  assert.equal(messages.length,1);assert.equal(messages[0].type,'EXPORT_DUTY_BRIEFING');
  assert.ok(messages[0].lines.some(s=>s.includes('FICTIONAL DEMO')));
  assert.ok(messages[0].lines.some(s=>s.startsWith('Departure UTC:')));
  assert.ok(messages[0].lines.includes('Pickup lobby'));ctx.closeBriefingDemo();assert.equal(ctx.briefingFlight(),null);
});
test('briefing renders three departure clocks and escapes preparation notes',()=>{
  const {ctx}=app();ctx.resetDef();const wrap={innerHTML:''};ctx.document.getElementById=id=>id==='dutyBriefing'?wrap:null;
  ctx.detectedFlights=[{flight:'CC102',depApt:'DFW',arrApt:'ICN',type:'intl',date:'2030-07-19',departureUtc:'2030-07-19T16:55:00Z'}];
  ctx.saveBriefingNote('<script>alert(1)</script>');ctx.renderDutyBriefing();
  assert.match(wrap.innerHTML,/DFW departure/);assert.match(wrap.innerHTML,/ICN home/);assert.match(wrap.innerHTML,/11:55/);assert.match(wrap.innerHTML,/01:55/);
  assert.match(wrap.innerHTML,/&lt;script>/);assert.doesNotMatch(wrap.innerHTML,/<script>alert/);
  assert.match(wrap.innerHTML,/Save \/ share briefing PDF/);
  wrap.contains=()=>true;ctx.document.activeElement={tagName:'INPUT',type:'checkbox'};
  ctx.toggleBriefingTask(0);assert.match(wrap.innerHTML,/1 \/ 4 checked/,'checking an item updates its timestamp and progress immediately');
});
test('interval reminders commit only after native acknowledgement and survive reload', () => {
  const {ctx,items,messages}=app();
  const fields={intervalLabel:{value:'Squat exercise'},intervalMinutes:{value:'90'}};
  ctx.document.getElementById=id=>fields[id] || null;
  ctx.addIntervalAlarm();
  assert.equal(messages[0].type,'SET_INTERVAL_ALARMS');
  assert.equal(messages[0].records[0].minutes,90);
  assert.equal(items.has('crewclock_intervals'),false);
  const saved=messages[0].records.map(a=>({...a,anchor:123456789}));
  ctx.intervalSyncResult(true,null,saved);
  ctx.loadIntervalAlarms();
  assert.equal(messages.at(-1).requestPermission,false);
  assert.equal(messages.at(-1).records[0].anchor,123456789);
  ctx.intervalSyncResult(true,null,saved);
  ctx.toggleIntervalAlarm(saved[0].id);
  assert.equal(messages.at(-1).records[0].enabled,false);
  ctx.intervalSyncResult(false,'Permission denied',null);
  assert.equal(ctx.intervalAlarms[0].enabled,true);
  ctx.deleteIntervalAlarm(saved[0].id);
  ctx.intervalSyncResult(true,null,[]);
  assert.equal(JSON.parse(items.get('crewclock_intervals')).length,0);
});
test('interval reminders reject empty names and invalid intervals',()=>{
  const {ctx,messages}=app();
  const fields={intervalLabel:{value:''},intervalMinutes:{value:'90'}};
  ctx.document.getElementById=id=>fields[id] || null;
  ctx.addIntervalAlarm();
  fields.intervalLabel.value='Exercise';
  for(const value of ['0','1.5','NaN','10081']){fields.intervalMinutes.value=value;ctx.addIntervalAlarm();}
  assert.equal(messages.length,0);
});
test('restore presets requires native confirmation and preserves personal data', () => {
  const { ctx, messages } = app();
  ctx.alms = [{ id: 'personal', type: 'direct', time: new Date('2030-01-01') }];
  ctx.detectedFlights = [{ id: 'flight' }];
  ctx.restoreAlarmDefaults();
  assert.equal(messages[0].type, 'CONFIRM_RESTORE_ALARMS');
  assert.equal(ctx.alms.length, 1);
  for (const name of ['renderBasePresets', 'renderDomPresets', 'renderIntlPresets', 'saveSettings', 'saveFlights', 'initFlightToggles', 'autoRegisterAll']) ctx[name] = () => {};
  ctx.baseOffs = [];
  ctx.restoreAlarmDefaults(true);
  assert.equal(ctx.baseOffs.length, 3);
  assert.equal(ctx.baseOffs[0].h, 4);
  assert.equal(ctx.baseOffs[0].m, 30);
  assert.equal(ctx.alms[0].id, 'personal');
  assert.equal(ctx.detectedFlights[0].id, 'flight');
});
test('browser restore cancellation leaves customized presets unchanged', () => {
  const { ctx } = app();
  delete ctx.window.crewclock;
  ctx.confirm = () => false;
  ctx.baseOffs = [{ id: 'custom', h: 9, m: 0 }];
  ctx.restoreAlarmDefaults();
  assert.equal(ctx.baseOffs[0].id, 'custom');
});
test('confirmed restore replaces flight alarms but keeps personal alarms', () => {
  const { ctx, messages } = app();
  for (const name of ['renderBasePresets', 'renderDomPresets', 'renderIntlPresets', 'syncAllPresets']) ctx[name] = () => {};
  ctx.detectedFlights = [{ id: 'flight', date: '2030-01-02', depTime: '12:00', type: 'base', flight: 'CC101', depApt: 'ICN', arrApt: 'LHR' }];
  ctx.alms = [{ id: 'personal', type: 'direct', time: new Date('2030-01-01') }, { id: 'old', type: 'base', time: new Date('2030-01-01') }];
  ctx.restoreAlarmDefaults(true);
  assert.equal(ctx.alms.length, 4);
  assert.ok(ctx.alms.some(a => a.id === 'personal'));
  assert.ok(!ctx.alms.some(a => a.id === 'old'));
  assert.equal(ctx.alms.find(a => a.id === 'flight_b1').time.toISOString(), '2030-01-01T22:30:00.000Z');
  assert.ok(messages.some(m => Array.isArray(m) && m.length === 4));
});
test('date and time appear together and theme is sent to Flutter', () => {
  const { ctx, messages } = app();
  const elements = { dDate: {}, dDateText: {} };
  ctx.document.getElementById = id => elements[id];
  ctx.drumY_val = 5; ctx.drumMo_val = 1; ctx.drumD_val = 27;
  ctx.drumH_val = 7; ctx.drumM_val = 5;
  ctx.updateDateDisplay();
  assert.equal(elements.dDate.value, '2030-02-28');
  assert.equal(elements.dDateText.textContent, '2030-02-28  07:05');
  ctx.syncNativeTheme(true);
  assert.deepEqual(messages[0], { type: 'SET_THEME', dark: true });
  assert.equal((html.match(/id="drumH"/g) || []).length, 1);
  assert.ok(html.indexOf('id="drumH"') > html.indexOf('id="dateSheet"'));
});
test('alarm calendar handles leap February, year rollover and keeps chosen time', () => {
  const { ctx } = app();
  const elements = { dDate: { value: '2028-02-29' }, dDateText: {}, alarmCalendarMonth: {}, alarmCalendarGrid: {} };
  ctx.document.getElementById = id => elements[id];
  ctx.alarmCalendarYear = 2028; ctx.alarmCalendarMonth = 1;
  ctx.drumH_val = 8; ctx.drumM_val = 15;
  ctx.renderAlarmCalendar();
  assert.equal((elements.alarmCalendarGrid.innerHTML.match(/<button /g) || []).length, 29);
  assert.ok(elements.alarmCalendarGrid.innerHTML.includes('aria-label="2028-02-29" aria-pressed="true"'));
  ctx.selectAlarmDate('2028-02-28');
  assert.equal(elements.dDateText.textContent, '2028-02-28  08:15');
  ctx.alarmCalendarMonth = 11;
  ctx.changeAlarmMonth(1);
  assert.equal(ctx.alarmCalendarYear, 2029);
  assert.equal(ctx.alarmCalendarMonth, 0);
  assert.equal(elements.dDate.value, '2028-02-28');
});
test('alarm month title restores today while keeping time; app title has no navigation', () => {
  const { ctx } = app();
  const fixed = new Date(2030, 0, 1, 0, 7);
  ctx.Date = class extends Date { constructor(...args) { super(...(args.length ? args : [fixed.getTime()])); } };
  const elements = { dDate: {}, dDateText: {}, alarmCalendarMonth: {}, alarmCalendarGrid: {} };
  ctx.document.getElementById = id => elements[id];
  ctx.setDrum = (id, value) => { if (id === 'drumH') ctx.drumH_val = value; else ctx.drumM_val = value; };
  ctx.drumY_val = 3; ctx.drumMo_val = 11; ctx.drumD_val = 30;
  ctx.drumH_val = 23; ctx.drumM_val = 59;
  ctx.resetAlarmDate();
  assert.equal(elements.dDateText.textContent, '2030-01-01  23:59');
  assert.equal(ctx.alarmCalendarYear, 2030);
  assert.equal(ctx.alarmCalendarMonth, 0);
  assert.ok(elements.alarmCalendarGrid.innerHTML.includes('aria-label="2030-01-01" aria-pressed="true"'));
  assert.ok(html.includes('onclick="resetAlarmDate()"'));
  assert.ok(html.includes('<div class="nav-title">'));
});
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
  ctx.clearAllData(true);
  assert.ok(messages.some(m => Array.isArray(m) && m.length === 0));
  assert.ok(messages.some(m => m.type === 'STOP_RINGING_ALARM'));
});
test('native delete asks Flutter for confirmation without deleting data', () => {
  const { ctx, messages } = app();
  ctx.alms = [{ id: 'keep' }];
  ctx.confirm = () => assert.fail('WebView confirm must not be used');
  ctx.clearAllData();
  assert.equal(ctx.alms.length, 1);
  assert.equal(messages.length, 1);
  assert.equal(messages[0].type, 'CONFIRM_DELETE_ALL');
});
test('browser delete cancellation preserves alarms', () => {
  const { ctx } = app();
  delete ctx.window.crewclock;
  ctx.confirm = () => false;
  ctx.alms = [{ id: 'keep' }];
  ctx.clearAllData();
  assert.equal(ctx.alms.length, 1);
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
  assert.deepEqual(dh.map(a=>new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(a.time))),['19:55','20:55','22:15']);
  const reduced=register('DH',true);
  assert.equal(reduced.length,2);
  assert.deepEqual(reduced,register('KE',true));
});

test('DFW UTC departure keeps the 19th local date when Korea is on the 20th', () => {
  const { ctx } = app();
  const f=ctx.parseICS('BEGIN:VEVENT\nDTSTART:20261020T025500Z\nDTEND:20261020T174000Z\nSUMMARY:KE032 DFW-ICN\nEND:VEVENT')[0];
  assert.equal(f.date,'2026-10-19');assert.equal(f.depTime,'21:55');
  assert.equal(f.arrDate,'2026-10-21');assert.equal(f.arrTime,'02:40');
  assert.equal(ctx.parseFlightDate(f).toISOString(),'2026-10-20T02:55:00.000Z');
  assert.equal(f.timingVersion,2);
});
test('floating and calendar-zone ICS both resolve to the same DFW instant', () => {
  const { ctx } = app();
  const floating=ctx.parseICS('BEGIN:VEVENT\nDTSTART:20261019T215500\nDTEND:20261021T024000\nSUMMARY:KE032 DFW-ICN\nEND:VEVENT')[0];
  const korea=ctx.parseICS('X-WR-TIMEZONE:Asia/Seoul\nBEGIN:VEVENT\nDTSTART:20261020T115500\nDTEND:20261021T024000\nSUMMARY:KE032 DFW-ICN\nEND:VEVENT')[0];
  assert.equal(floating.departureUtc,'2026-10-20T02:55:00.000Z');
  assert.equal(korea.departureUtc,floating.departureUtc);
  assert.equal(korea.date,'2026-10-19');assert.equal(korea.depTime,'21:55');
  const allDay=ctx.parseICS('BEGIN:VEVENT\nDTSTART;VALUE=DATE:20261019\nDTEND;VALUE=DATE:20261020\nSUMMARY:KE032 DFW 21:55-ICN 02:40\nEND:VEVENT')[0];
  assert.equal(allDay.departureUtc,floating.departureUtc);
  assert.equal(allDay.arrivalUtc,floating.arrivalUtc);
});
test('DFW stay drives today and manual alarms, then switches on arrival in Korea', () => {
  const { ctx } = app();
  let now=new Date('2026-10-20T01:25:00Z');
  ctx.Date=class extends Date { constructor(...args){super(...(args.length?args:[now.getTime()]));} };
  ctx.detectedFlights=ctx.parseICS('BEGIN:VEVENT\nDTSTART:20261017T002000Z\nDTEND:20261017T131000Z\nSUMMARY:KE031 ICN-DFW\nEND:VEVENT\nBEGIN:VEVENT\nDTSTART:20261020T025500Z\nDTEND:20261020T174000Z\nSUMMARY:KE032 DFW-ICN\nEND:VEVENT');
  assert.equal(ctx.stayAirport(),'DFW');assert.equal(ctx.appZone(),'America/Chicago');
  assert.equal(ctx.todayStr(),'2026-10-19');
  assert.equal(ctx.buildDate('2026-10-19',22,0).toISOString(),'2026-10-20T03:00:00.000Z');
  const departure=ctx.parseFlightDate(ctx.detectedFlights[1]);
  const alarm=new Date(departure.getTime()-3*3600000);
  assert.equal(alarm.toISOString(),'2026-10-19T23:55:00.000Z');
  assert.equal(ctx.dayKeyFromDate(alarm),'2026-10-19');assert.equal(ctx.fmt(alarm),'18:55');
  ctx.resetDef();ctx.initFlightToggles();ctx.document.getElementById=()=>null;
  ctx.autoRegisterAll();
  assert.ok(ctx.alms.some(a=>a.fnum==='KE032'),'the DFW flight is not discarded as yesterday in Korea');
  assert.ok(ctx.alms.filter(a=>a.fnum==='KE032').every(a=>a.dep.toISOString()==='2026-10-20T02:55:00.000Z'));
  now=new Date('2026-10-20T18:00:00Z');
  assert.equal(ctx.stayAirport(),'ICN');assert.equal(ctx.todayStr(),'2026-10-21');
  assert.equal(ctx.parseFlightDate(ctx.detectedFlights[1]).toISOString(),departure.toISOString());
});
test('unknown floating ICS airports and DST ambiguity never silently schedule', () => {
  const { ctx } = app();
  assert.throws(()=>ctx.parseICS('BEGIN:VEVENT\nDTSTART:20261019T215500\nSUMMARY:ZZ1 ZZZ-ICN\nEND:VEVENT'),/Unknown departure time zone/);
  assert.throws(()=>ctx.parseICS('BEGIN:VEVENT\nDTSTART:20261101T013000\nSUMMARY:KE032 DFW-ICN\nEND:VEVENT'),/ambiguous/);
});

test('sample roster previews future flights without saving or changing existing alarms', () => {
  const { ctx, messages } = app();
  const elements = {};
  ctx.document.getElementById = id => elements[id] ||= { value: '', focus() {}, scrollIntoView() {}, style: {} };
  ctx.setImportMode = () => {};
  ctx.alms = [{ id: 'existing' }];
  ctx.detectedFlights = [{ id: 'existing-flight' }];
  const fixed = new Date(2030, 11, 31, 12);
  ctx.Date = class extends Date { constructor(...args) { super(...(args.length ? args : [fixed.getTime()])); } };
  ctx.previewSampleRoster();
  assert.equal(ctx.manualImportDraft.flights.length, 2);
  assert.equal(ctx.manualImportDraft.flights[0].date, '2031-01-02');
  assert.equal(ctx.manualImportDraft.flights[0].flight, 'ZZ101');
  assert.equal(ctx.alms[0].id, 'existing');
  assert.equal(ctx.detectedFlights[0].id, 'existing-flight');
  assert.equal(messages.length, 0);
  assert.match(elements.manualStatus.textContent, /Fictional sample preview only/);
});

test('confirming manual date and time registers once and rejects past times', () => {
  const { ctx, messages } = app();
  const elements = {};
  ctx.document.getElementById = id => elements[id] ||= { value: '', classList: { remove() {} } };
  ctx.scheduleNotificationsViaSW = () => {};
  ctx.drumY_val = 10; ctx.drumMo_val = 0; ctx.drumD_val = 1;
  ctx.drumH_val = 8; ctx.drumM_val = 15;
  ctx.document.getElementById('dLabel').value = 'Wake up';
  ctx.confirmDate();
  assert.equal(ctx.alms.length, 1);
  assert.equal(ctx.alms[0].lbl, 'Wake up');
  assert.equal(ctx.alms[0].time.getHours(), 8);
  assert.equal(ctx.alms[0].time.getMinutes(), 15);
  assert.ok(messages.some(m => Array.isArray(m) && m.length === 1));
  ctx.confirmDate();
  assert.equal(ctx.alms.length, 1);
  ctx.drumY_val = 0;
  ctx.confirmDate();
  assert.equal(ctx.alms.length, 1);
});

test('November roster imports Prague legs and keeps departure-local alarm instants', () => {
  const {ctx}=app();
  ctx.Date=class extends Date { constructor(...args) { super(...(args.length ? args : ['2026-10-21T00:00:00Z'])); } };
  const legs=[
    ['20261102T135500','20261102T200500','KE 955 ICN - IST'],
    ['20261104T215500','20261105T135500','KE 956 IST - ICN'],
    ['20261111T105000','20261111T162000','KE 969 ICN - PRG'],
    ['20261113T183000','20261114T135000','KE 970 PRG - ICN'],
    ['20261120T105000','20261120T162000','KE 969 ICN - PRG'],
    ['20261121T183000','20261122T135000','KE 970 PRG - ICN']
  ];
  const events=legs.map(([start,end,summary])=>`BEGIN:VEVENT\r\nDTSTART:${start}\r\nDTEND:${end}\r\nSUMMARY:${summary}\r\nEND:VEVENT`);
  events.push('BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261101\r\nSUMMARY:RESERVE - ICN\r\nEND:VEVENT');
  events.push('BEGIN:VEVENT\r\nDTSTART:20261126T090000\r\nDTEND:20261126T103000\r\nSUMMARY:KCRM1.5 - GMP\r\nEND:VEVENT');
  const flights=ctx.parseICS('BEGIN:VCALENDAR\r\n'+events.join('\r\n')+'\r\nEND:VCALENDAR');
  assert.equal(flights.length,6);
  const prague=flights.find(f=>f.flight==='KE970');
  assert.equal(prague.depTime,'18:30');
  assert.equal(prague.date,'2026-11-13');
  assert.equal(prague.departureUtc,'2026-11-13T17:30:00.000Z');
  assert.equal(prague.arrivalUtc,'2026-11-14T04:50:00.000Z');
  assert.equal(ctx.dayKeyFromCivilDate(ctx.dateAtZone(new Date(prague.departureUtc),'Asia/Seoul')),'2026-11-14');
  ctx.detectedFlights=flights;
  ctx.document.getElementById=()=>null;
  ctx.resetDef();
  ctx.initFlightToggles();ctx.autoRegisterAll();
  const wake=ctx.alms.find(a=>a.id===prague.id+'_i1');
  assert.equal(wake.time.toISOString(),'2026-11-13T14:30:00.000Z');
  assert.equal(ctx.alarmTimeText(wake,wake.time),'15:30');
  assert.equal(ctx.parseICSDate('20260715T183000',ctx.airportZone('PRG')).toISOString(),'2026-07-15T16:30:00.000Z');
});

test('today and future schedule alarms stay vivid while past dates are dimmed', () => {
  const { ctx } = app();
  let now = new Date(2030, 0, 1, 12);
  ctx.Date = class extends Date { constructor(...args) { super(...(args.length ? args : [now.getTime()])); } };
  const elements = {};
  ctx.document.getElementById = id => elements[id] ||= { style: {} };
  ctx.detectedFlights = [{ id: 'next', date: '2030-01-03', depTime: '09:20', flight: 'KE031', depApt: 'ICN', arrApt: 'DFW', type: 'base' }];
  ctx.baseOffs = [{ id: 'b1', h: 4, m: 30, lbl: 'Prepare for Duty' }];
  ctx.flightToggles = { next: { b1: true } };
  ctx.alms = [{ id: 'today', type: 'direct', time: new Date(2030, 0, 1, 18), lbl: 'Today alarm' }];
  vm.runInContext(script.slice(script.indexOf('function renderDaySchedule('), script.indexOf('function renderHomeFlightList(')), ctx);
  ctx.renderDaySchedule('2030-01-01');
  assert.equal(elements.nextDayCard.style.display, 'block');
  assert.equal(elements.dayCard.style.display, 'block');
  assert.match(elements.dayFlights.innerHTML, /Today alarm/);
  assert.equal(elements.nextDayTitle.textContent, '01/03 Thu');
  assert.equal(elements.nextDayTitle.title, '2030-01-03');
  assert.match(elements.nextDayFlightHeaderInfo.innerHTML, /KE031/);
  assert.match(elements.nextDayFlights.innerHTML, /Prepare for Duty/);
  assert.match(elements.nextDayFlights.innerHTML, /04:50\(L\)/);
  assert.doesNotMatch(elements.nextDayFlights.innerHTML, /<small|ICN local/);
  assert.match(elements.nextDayFlights.innerHTML, /\(-4h30m\)/);
  assert.doesNotMatch(elements.nextDayFlights.innerHTML, /opacity:0.45/);
  ctx.alms=[];
  ctx.renderDaySchedule('2030-01-01');
  assert.equal(elements.dayCard.style.display, 'none', 'empty selected date does not leave a blank card');
  assert.equal(elements.nextDayCard.style.display, 'block', 'upcoming alarms remain visible');
  ctx.flightToggles.next.b1=false;
  ctx.renderDaySchedule('2030-01-01');
  assert.equal(elements.nextDayCard.style.display, 'none', 'an upcoming date without alarms is also hidden');
  ctx.flightToggles.next.b1=true;
  now = new Date(2030, 0, 3, 0, 1);
  ctx.renderDaySchedule('2030-01-03');
  assert.equal(elements.dayCard.style.display, 'block', 'selecting a date with alarms restores its card');
  assert.equal(elements.nextDayCard.style.display, 'none');
  assert.match(elements.dayFlights.innerHTML, /Prepare for Duty/);
  assert.doesNotMatch(elements.dayFlights.innerHTML, /opacity:0.45/);
  now = new Date(2030, 0, 4, 12);
  ctx.renderDaySchedule('2030-01-03');
  assert.match(elements.dayFlights.innerHTML, /Prepare for Duty/);
  assert.match(elements.dayFlights.innerHTML, /opacity:0.45/, 'selecting a past schedule also dims its preview alarms');
});
