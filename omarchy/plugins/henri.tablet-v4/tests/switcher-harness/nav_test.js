// node nav_test.js — the switcher's and the gesture navigation's arithmetic (switcher/Nav.js)
const fs = require('fs'), path = require('path'), assert = require('assert')
const src = fs.readFileSync(path.join(__dirname, '../../switcher/Nav.js'), 'utf8').replace('.pragma library', '')
const Nav = new Function(src + '\nreturn { rubber, trim, velocity, bounds, slot, follow, settle, centred, classify, lifted, pull, decide }')()
const cfg = { cardDismiss: 0.3, flick: 500 }
const nav = { homeFlick: 1200, travel: 48 }
const near = (a, b) => Math.abs(a - b) < 1e-6
let n = 0
const t = (name, fn) => { fn(); n++; console.log('ok', name) }

t('rubber gives less and less, never past its limit', () => {
  assert(Nav.rubber(0, 100) === 0)
  assert(Nav.rubber(100, 100) === 50)
  assert(Nav.rubber(1e9, 100) < 100)
})
t('velocity over the samples, 0 once the finger rested', () => {
  const s = [[0, 0, 0], [50, 100, -50]]
  const v = Nav.velocity(s, 60, 80)
  assert(near(v.x, 2000) && near(v.y, -1000))
  assert(Nav.velocity(s, 200, 80).x === 0)
  assert(Nav.trim([[0, 0, 0], [10, 0, 0], [100, 0, 0]], 100, 80).length === 2)
})
t('slots: the newest (last) card in the middle at offset 0', () => {
  assert(Nav.slot(4, 5, 300) === 0)
  assert(Nav.slot(0, 5, 300) === -1200)
  const b = Nav.bounds(5, 300)
  assert(b.lo === 0 && b.hi === 1200)
  assert(Nav.bounds(0, 300).hi === 0)
  assert(Nav.centred(0, 5, 300) === 4 && Nav.centred(1200, 5, 300) === 0 && Nav.centred(320, 5, 300) === 3)
})
t('follow is 1:1 inside, rubber past the ends', () => {
  assert(Nav.follow(300, 100, 0, 1200, 170) === 400)
  const past = Nav.follow(0, -500, 0, 1200, 170)
  assert(past < 0 && past > -170)
  assert(Nav.follow(1200, 500, 0, 1200, 170) < 1370)
})
t('settle: a fling carries on, then the nearest card, inside the row', () => {
  assert(Nav.settle(310, 0, 300, 0, 1200, 0.25) === 300)
  assert(Nav.settle(310, 2000, 300, 0, 1200, 0.25) === 900)   // 310 + 500 = 810 → 900
  assert(Nav.settle(310, -4000, 300, 0, 1200, 0.25) === 0)
  assert(Nav.settle(900, 9000, 300, 0, 1200, 0.25) === 1200)
})
t('classify: a tap, the row, or a card lifted', () => {
  assert(Nav.classify(3, 3, 8, true) === '')
  assert(Nav.classify(30, 5, 8, true) === 'row')
  assert(Nav.classify(2, -30, 8, true) === 'lift')
  assert(Nav.classify(2, -30, 8, false) === 'row')
  assert(Nav.classify(2, 30, 8, true) === 'row')
})
t('a lifted card closes far or fast, else drops back', () => {
  assert(Nav.lifted(-200, 0, 528, cfg) === 'close')
  assert(Nav.lifted(-100, 0, 528, cfg) === 'back')
  assert(Nav.lifted(-40, -900, 528, cfg) === 'close')
})
t('navigation: pull follows the finger, a flick goes home only with a way home', () => {
  assert(Nav.pull(0, 960, 0.3) === 0 && near(Nav.pull(144, 960, 0.3), 0.5) && Nav.pull(900, 960, 0.3) === 1)
  assert(Nav.decide(200, -2000, true, nav) === 'home')
  assert(Nav.decide(200, -2000, false, nav) === 'switcher')
  assert(Nav.decide(30, -2000, false, nav) === 'back')
  assert(Nav.decide(60, 0, true, nav) === 'switcher')
  assert(Nav.decide(20, 0, true, nav) === 'back')
})
console.log(`${n} passed`)
