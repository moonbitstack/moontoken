// The pages trust these three functions to say what the library did, so what
// they report is worth pinning: the table the pages print, the counts they show,
// and the round trip they claim.

///|
test "the specimen table carries every byte and the merges on top" {
  let ranks = specimen()
  assert_eq(ranks.length(), 285)
  assert_eq(ranks.missing_bytes().length(), 0)
  assert_eq(ranks.token(258), Some(@utf8.encode("the")))
}

///|
test "text the table has merged costs one token per piece" {
  let tokenizer = specimen_tokenizer()
  let ids = tokenizer.encode("the world and the thing")
  assert_eq(ids.length(), 7)
  assert_eq(ids[0], 258)
  assert_eq(tokenizer.decode(ids), "the world and the thing")
}

///|
test "a script the table never merged costs three tokens a character" {
  let tokenizer = specimen_tokenizer()
  let ids = tokenizer.encode("分词器")
  assert_eq(ids.length(), 9)
  assert_eq(tokenizer.decode(ids), "分词器")
}

///|
test "the page's answer carries the counts and the decoded text" {
  let report = compose("the world and the thing")
  assert_true(report.contains("\"count\":7"))
  assert_true(report.contains("\"bytes\":23"))
  assert_true(report.contains("\"decoded\":\"the world and the thing\""))
}

///|
test "an empty text is answered, not refused" {
  let report = compose("")
  assert_true(report.contains("\"count\":0"))
  assert_true(report.contains("\"decoded\":\"\""))
}

///|
test "the type case has one entry per id" {
  let report = table()
  assert_true(report.contains("\"vocabulary\":285"))
  let mut entries = 0
  for _ in report.split("\"id\":") {
    entries = entries + 1
  }
  assert_eq(entries - 1, 285)
}
