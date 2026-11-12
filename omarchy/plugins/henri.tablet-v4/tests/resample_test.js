// node tests/resample_test.js — Resample.js: one point per frame between stepped finger points
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '..', 'Resample.js'), 'utf8').replace('.pragma library', '')
const R = new Function(src + '; return { create }')()
let n = 0, bad = 0
function ok(c, m) { n++; if (!c) { bad++; console.log('FAIL', m) } }
const r = R.create(8, 70)
ok(r.at(0) === null, 'nothing before the first point')
r.push(0, 0, 100)
ok(r.at(5).y === 100, 'the first point at once')
r.push(44, 0, 56)                       // a step of 44 px after 44 ms
const mid = r.at(44 + 28).y
ok(mid < 100 && mid > 56, 'glides between the points: ' + mid)
ok(r.at(44 + 200).y === 56, 'reaches a resting finger')
r.push(300, 0, 0)                       // after a pause: the gap stays within maxGap
ok(r.at(300 + 70).y === 0, 'a pause does not drag the glide past maxGap')
// continuity: a new point mid-glide starts from where it stands
const r2 = R.create(8, 70)
r2.push(0, 0, 0); r2.push(40, 40, 0)
const before = r2.at(60).x
r2.push(60, 80, 0)
ok(Math.abs(r2.at(60).x - before) < 1e-9, 'no jump when a point arrives mid-glide')
console.log(bad ? `${bad} of ${n} failed` : `${n} passed`)
process.exit(bad ? 1 : 0)
