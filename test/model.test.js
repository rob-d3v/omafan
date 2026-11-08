// Run with: node --test test/
const test = require("node:test")
const assert = require("node:assert")
const Model = require("../Model.js")

const status = `Read-only                : false
Selected Config Name     : Acer Nitro AN515-44

Fan Display Name         : CPU fan
Temperature              : 84.44
Auto Control Enabled     : true
Critical Mode Enabled    : false
Current Fan Speed        : 60.49
Target Fan Speed         : 94.00
Fan Speed Steps          : 6122

Fan Display Name         : GPU fan
Temperature              : 71.00
Auto Control Enabled     : true
Critical Mode Enabled    : false
Current Fan Speed        : 94.23
Target Fan Speed         : 94.00
Fan Speed Steps          : 6122
`

test("parses the service and every fan", () => {
  const parsed = Model.parseStatus(status)
  assert.strictEqual(parsed.config, "Acer Nitro AN515-44")
  assert.strictEqual(parsed.readOnly, false)
  assert.strictEqual(parsed.fans.length, 2)
  assert.deepStrictEqual(parsed.fans[0], {
    name: "CPU fan", temperature: 84.44, auto: true, critical: false, current: 60.49, target: 94
  })
})

test("empty or garbage output parses to no fans", () => {
  assert.deepStrictEqual(Model.parseStatus("").fans, [])
  assert.deepStrictEqual(Model.parseStatus("ERROR: nbfc: Could not connect").fans, [])
})

test("markup-shaped names are kept as plain bounded text", () => {
  const parsed = Model.parseStatus("Fan Display Name : <img src=x>" + "a".repeat(200))
  assert.ok(parsed.fans[0].name.startsWith("<img src=x>"))
  assert.strictEqual(parsed.fans[0].name.length, 60)
})

test("mode reads auto, manual, and mixed", () => {
  const auto = Model.parseStatus(status).fans
  assert.strictEqual(Model.mode(auto).kind, "auto")
  const manual = auto.map(f => ({ ...f, auto: false, target: 75 }))
  assert.deepStrictEqual(Model.mode(manual), { kind: "manual", speed: 75 })
  assert.strictEqual(Model.presetForMode(Model.mode(manual)), "75")
  const stopped = auto.map(f => ({ ...f, auto: false, target: 0 }))
  assert.strictEqual(Model.presetForMode(Model.mode(stopped)), "0")
  assert.deepStrictEqual(Model.setCommand("0", 0), ["nbfc", "set", "-s", "0", "-f", "0"])
  manual[1].target = 40
  assert.strictEqual(Model.mode(manual).kind, "mixed")
  assert.strictEqual(Model.mode([]).kind, "none")
})

test("hottest and heat bands", () => {
  const fans = Model.parseStatus(status).fans
  assert.strictEqual(Model.hottest(fans), 84.44)
  assert.strictEqual(Model.heat(60), "calm")
  assert.strictEqual(Model.heat(75), "warm")
  assert.strictEqual(Model.heat(90), "hot")
})

test("set commands are clamped whole percentages", () => {
  assert.deepStrictEqual(Model.setCommand("auto"), ["nbfc", "set", "-a"])
  assert.deepStrictEqual(Model.setCommand(72.6), ["nbfc", "set", "-s", "73"])
  assert.deepStrictEqual(Model.setCommand(150), ["nbfc", "set", "-s", "100"])
  assert.strictEqual(Model.setCommand("; rm -rf ~"), null)
  assert.deepStrictEqual(Model.setCommand(40, 1), ["nbfc", "set", "-s", "40", "-f", "1"])
  assert.deepStrictEqual(Model.setCommand("auto", 0), ["nbfc", "set", "-a", "-f", "0"])
  assert.deepStrictEqual(Model.setCommand("auto", -1), ["nbfc", "set", "-a"])
  assert.deepStrictEqual(Model.setCommand(40, "1; rm"), ["nbfc", "set", "-s", "40"])
})

test("critical mode wins over the asked speed", () => {
  const fans = Model.parseStatus(status).fans.map(f => ({ ...f, auto: false, critical: true, target: 100 }))
  assert.strictEqual(Model.mode(fans).kind, "critical")
  assert.strictEqual(Model.presetForMode(Model.mode(fans)), "")
})

test("one fan or all of them", () => {
  const fans = Model.parseStatus(status).fans
  assert.strictEqual(Model.targetFans(fans, -1).length, 2)
  assert.strictEqual(Model.targetFans(fans, 1)[0].name, "GPU fan")
  assert.strictEqual(Model.targetFans(fans, 5).length, 2)
})

test("fan kinds from nbfc names", () => {
  assert.strictEqual(Model.fanKind("Ryzen 4600H", 0).kind, "cpu")
  assert.strictEqual(Model.fanKind("NVIDIA GeForce GTX 1650", 1).kind, "gpu")
  assert.deepStrictEqual(Model.fanKind("Fan #3", 2), { kind: "fan", number: 3 })
})

test("digit shortcuts", () => {
  assert.strictEqual(Model.speedForDigit("3"), 30)
  assert.strictEqual(Model.speedForDigit("0"), 100)
  assert.ok(Number.isNaN(Model.speedForDigit("a")))
})
