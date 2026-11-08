// Fan names and nbfc errors come from another process, so no Text in the
// widget may fall back to Qt's AutoText, which would render markup.
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "Widget.qml"), "utf8")

test("every Text is plain text", () => {
  const bare = source.split("\n").filter(line => /^\s*Text\s*\{/.test(line))
  assert.deepStrictEqual(bare, [], "use the PlainText component instead of Text")
  assert.match(source, /component PlainText: Text \{\n\s*textFormat: Text\.PlainText/)
})
