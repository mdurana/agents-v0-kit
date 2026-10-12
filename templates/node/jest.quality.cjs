/** Jest gate for the node pack. Writes junit.xml and coverage/coverage-summary.json. */
module.exports = {
  testEnvironment: "node",
  coverageDirectory: "coverage",
  coverageReporters: ["text", "json-summary"],
  reporters: [
    "default",
    ["jest-junit", { outputFile: "junit.xml" }],
  ],
};
