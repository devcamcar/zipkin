/*
* Copyright 2012 Twitter Inc.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

package com.twitter.zipkin.hadoop

import email.EmailContent
import java.io._
import collection.mutable.HashMap
import com.twitter.zipkin.hadoop.sources.Util

/**
 * A client which writes to a file. This is intended for use mainly to format emails
 * @param combineSimilarNames
 * @param jobname
 */

abstract class WriteToFileClient(combineSimilarNames: Boolean, jobname: String) extends HadoopJobClient(combineSimilarNames) {

  protected var outputDir = ""

  def toHtmlName(s: String) = outputDir + "/" + Util.toSafeHtmlName(s) + ".html"

  def start(input: String, outputDir: String) {
    this.outputDir = outputDir
    processDir(new File(input))
  }
}

/**
 * A client which writes MemcacheRequest data to the file specified
 */

class MemcacheRequestClient extends WriteToFileClient(true, "MemcacheRequest") {

  def processKey(service: String, lines: List[LineResult]) {
    val numberMemcacheRequests = {
      val valuesToInt = lines.map({ line: LineResult => augmentString(line.getValueAsString()).toInt })
      valuesToInt.foldLeft(0) ((left: Int, right: Int) => left + right )
    }
    val mt = EmailContent.getTemplate(service)
    mt.addOneLineResult(service, "Service " + service + " made " + numberMemcacheRequests + " redundant memcache requests")
  }

}

/**
 * A client which writes to a file, per each service pair
 */

abstract class WriteToTableClient(jobname: String) extends WriteToFileClient(false, jobname) {

  def getTableResultHeader(service: String): String

  def getTableHeader(): List[String]

  def addTable(service: String, lines: List[LineResult], mt: EmailContent) = {
    mt.addTableResult(service, getTableResultHeader(service), getTableHeader(), lines)
  }

  def processKey(service: String, lines: List[LineResult]) {
    val mt = EmailContent.getTemplate(service)
    addTable(service, lines, mt)
  }
}


/**
 * A client which writes Timeouts data to the file specified
 */

class TimeoutsClient extends WriteToTableClient("Timeouts") {

  def getTableResultHeader(service: String) = {
    service + " timed out in calls to the following services"
  }

  def getTableHeader() = {
    List("Service Called", "# of Timeouts")
  }
}


/**
 * A client which writes Retries data to the file specified
 */

class RetriesClient extends WriteToTableClient("Retries") {

  def getTableResultHeader(service: String) = {
    service + " retried in calls to the following services:"
  }

  def getTableHeader() = {
    List("Service Called", "# of Retries")
  }
}


/**
 * A client which writes WorstRuntimes data to the file specified
 */

class WorstRuntimesClient extends WriteToTableClient("WorstRuntimes") {

  def getTableResultHeader(service: String) = {
    "Service " + service + " took the longest for these spans:"
  }

  def getTableHeader() = {
    List("Span ID", "Duration (ms)")
  }
}


/**
 * A client which writes WorstRuntimesPerTrace data to the file specified. Formats it as a HTML url
 */

class WorstRuntimesPerTraceClient(zipkinUrl: String) extends WriteToTableClient("WorstRuntimesPerTrace") {

  def getTableResultHeader(service: String) = {
    "Service " + service + " took the longest for these traces:"
  }

  def getTableHeader() = {
    List("Trace ID", "Duration (ms)")
  }

  override def addTable(service: String, lines: List[LineResult], mt: EmailContent) = {
    val formattedAsUrl = lines.flatMap {line =>
      if (line.getValue().length < 2) {
        throw new IllegalArgumentException("Malformed line: " + line)
      }
      val hypertext = line.getValue().head
      val duration = augmentString(line.getValue().tail.head).toFloat
      if (duration > 1000) {
        val inMilliseconds = scala.math.round(duration * 100 / 1000.0) / 100.0
        val formatted = new PerServiceLineResult((List(line.getKey(), hypertext, inMilliseconds.toString)))
        Some((zipkinUrl + hypertext, hypertext, formatted))
      } else {
        None
      }
    }
    if (formattedAsUrl.length > 0) {
      mt.addUrlTableResult(service, getTableResultHeader(service), getTableHeader(), formattedAsUrl)
    }
  }
}


/**
 * A client which writes ExpensiveEndpoints data to the file specified
 */

class ExpensiveEndpointsClient extends WriteToTableClient("ExpensiveEndpoints") {

  def getTableResultHeader(service: String) = {
    "The most expensive calls for " + service + " were:"
  }

  def getTableHeader() = {
    List("Service Called", "Duration (ms)")
  }

  override def addTable(service: String, lines: List[LineResult], mt: EmailContent) = {
    val formatted = lines.map {line =>
      if (line.getValue().length < 2) {
        throw new IllegalArgumentException("Malformed line: " + line)
      }
      val service = line.getValue().head
      val duration = augmentString(line.getValue().tail.head).toFloat
      val rounded = scala.math.round(duration * 100) / 100.0
      new PerServiceLineResult((List(line.getKey(), service, rounded.toString)))
    }
    if (formatted.length > 0) {
      mt.addTableResult(service, getTableResultHeader(service), getTableHeader(), formatted)
    }
  }
}
