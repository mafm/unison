package org.unisonweb

import org.unisonweb.EasyTest._
import org.unisonweb.util.{StreamTests, UtilTests}

object AllTests {
  val tests = suite(
    DecompileTests.tests,
    UtilTests.tests,
    CompilationTests.tests,
    CodecsTests.tests,
    StreamTests.tests
  )
}

object RunAllTests {
  def main(args: Array[String]) = args match {
    case Array(prefix) =>
      run(prefix = prefix)(AllTests.tests)
    case Array(seed, prefix) =>
      run(seed = seed.toLong, prefix = prefix)(AllTests.tests)
    case _ => run()(AllTests.tests)
  }
}
