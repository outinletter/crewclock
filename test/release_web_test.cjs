const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, '../assets/html/index.html'), 'utf8');
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
  ctx.document.getElementById = id => els.get(id) || { value: '', classList: { add(){}, remove(){} }, style:{} };
  ctx.replaceMonthFlights = flights => { ctx.__flights = flights; return flights.length; };
  ctx.initFlightToggles = ctx.autoRegisterAll = ctx.saveFlights = ctx.renderHomeFlightList = ctx.renderSheetFalWrap = ctx.renderCal = ctx.renderDaySchedule = () => {};
  ctx.parseManualEntry();
  assert.equal(ctx.__flights.length, 1);
  assert.equal(ctx.__flights[0].flight, 'KE913');
  assert.equal(ctx.__flights[0].date, '2025-06-03');
  assert.equal(ctx.__flights[0].depApt, 'ICN');
  assert.equal(ctx.__flights[0].arrApt, 'MAD');
});
