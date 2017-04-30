#!/usr/bin/python

# a script for analyzing RCP data. the goal here is to do things like look at long
# term trends over multiple races.

import csv
import collections
import logging
import os
import numpy
import argparse

# set log level
logging.basicConfig(level=logging.INFO)

class RcpLog:
    """this class represents an RCP log file.
    """
    @staticmethod
    def loadAndMergeDirectory(path):
        """loads all the .LOG files in the given directory and merges them together.
           this should result in one huge log object that represents all the data
           in the directory.
        """
        # list the files in the directory and sort them for the .LOG extension all at once
        logs = [x for x in os.listdir(path) if os.path.splitext(x)[1] == '.LOG']

        # sort the logs by filesize to hide my dumb repeated parsing problem (for now)
        logs = sorted(logs, key=lambda name: os.path.getsize(os.path.join(path, name)))

        # we have to start with something, so load up the first log in the list.
        retval = RcpLog(os.path.join(path, logs[0]), skipParse = True)

        # now load all the rest of the logs and merge them with this log.
        for logname in logs[1:]:
            log = RcpLog(os.path.join(path, logname), skipParse = True)
            retval.merge(log)

        # at the very end, do the parsing, only once...
        logging.info('turning parsing back on for %d rawlines!', len(retval.rawlines))
        retval.skipParse = False
        retval.parseRawlines()

        return retval

    def __init__(self, filename=None, skipParse=False):
        """the constructor. load the file if one was specified, otherwise set everything
           to null.
           skipParse is a workaround for the multiple parsing madness that happens if you
           open a file only to immediately merge it with another file and then merge that
           result with yet more files. if it is true, you won't do any actual parsing until
           it is reset to false.
        """
        # setup all the instance fields
        self.filename = filename
        self.skipParse = skipParse
        self.descriptions = []
        self.nameToDescriptionDict = {}
        self.data = {}
        self.rawlines = []

        # generate some named tuples for storing data the lazy way.
        # this are almost certainly things that should be their own classes...
        self.DataDescription = collections.namedtuple('DataDescription',
                ['name', 'unit', 'min', 'max', 'frequency'])
        self.DataPoint = collections.namedtuple('DataPoint',
                ['timestamp', 'value'])

        if filename is not None:
            # load if possible.
            self.load()

    def load(self):
        """load the log from the path in self.filename
        """
        logging.info('loading %s...', self.filename)
        with open(self.filename, 'r') as f:
            reader = csv.reader(f)
            self.rawlines = [line for line in reader]
            logging.info("read %d lines", len(self.rawlines))
            self.parseRawlines()

    def merge(self, other):
        """merge other log into this log. this is handy since the RCP writes
           a new log file every time it stops logging. this will do things the
           kind of dumb way for now and just merge the raw lines, sort them by
           timestamp and then reparse everything
           NOTE: the headers for both logs had better be the same. if they aren't,
                 this process should fail...
        """
        logging.info('attempting to merge %s and %s', self.filename, other.filename)

        if self.headerLine != other.headerLine:
            logging.error("can not merge logs! headers don't match!")
            logging.error(str(map(None, self.headerLine, other.headerLine)))
            return

        # assuming we are in the case where the headers match, start by merging
        # the other rawlines into self.rawlines, making sure to skip the second header
        logging.info('adding %d new lines to the existing %d lines',
                len(other.rawlines), len(self.rawlines))
        self.rawlines += other.rawlines[1:]

        # now sort the rawlines by UTC timestamp, which I'm pretty sure is always the
        # second field
        logging.info('sorting rawlines...')
        # mildly annoying sort while keeping the first line where it belongs
        self.rawlines = self.rawlines[:1] + sorted(self.rawlines[1:],key=lambda line: line[1])
        logging.info('sorting complete!')
        # now reparse the newly longer rawlines
        self.parseRawlines()

    def parseRawlines(self):
        """this method is kind of part of load, but it also makes it way easier
           to merge files and then reparse the resulting concatenated rawlines
        """
        logging.info('parsing %d lines', len(self.rawlines))
        # the file always begins with the header line
        self.headerLine = self.rawlines[0]

        # make sure to reset the descriptions and data members. this becomes important
        # when we start merging files together
        self.descriptions = []
        self.data = {}
        self.nameToDescriptionDict = {}

        logging.info('got %d data fields', len(self.headerLine))

        # now parse out the header into descriptions.
        for field in self.headerLine:
            splitField = field.split('|')
            description = self.DataDescription(name=splitField[0],
                    unit=splitField[1].strip('"'),
                    min=splitField[2],
                    max=splitField[3],
                    frequency=splitField[4]
            )
            # append this DataDescription to the sorted array
            self.descriptions.append(description)
            # and make sure the new description has an entry in the data dict
            self.data[description] = []
            self.nameToDescriptionDict[description.name] = description

            logging.info('found new field %s', description.name)

        if self.skipParse:
            return

        # now parse all the raw data into DataPoints
        for line in self.rawlines[1:]:
            # UTC time in milliseconds is always the second entry
            # I think it is sort of safe to assume that...
            # sadly, sometimes there is a totally blank line at the start of the log, so
            # if there is no timestamp, just skip the line and print a warning.
            if line[1] == '':
                logging.warning('skipping apparently empty line %s', line)
                continue

            timestamp = int(line[1])

            for i in xrange(len(self.descriptions)):
                if line[i] != '':
                    # many fields are empty because some sensors log at way higher
                    # rates than others. we only care about the data that's actually there.
                    # I'm also assuming everything is a float for now...
                    self.data[self.descriptions[i]].append(
                            self.DataPoint(timestamp=timestamp, value=float(line[i])))

        # fire off a quick logging message about what we just loaded.
        for description in self.descriptions:
            logging.info("Parsed %d %s records", len(self.data[description]), description.name)

    def printStats(self):
        """print some basic statistics on the data to the logger...
        """
        # for now, loop over each kind of data and print some stats...
        for description in self.descriptions:
            d = self.data[description]
            values = [x.value for x in d]
            meanVal = numpy.mean(values)
            maxVal = numpy.max(values)
            minVal = numpy.min(values)
            std = numpy.std(values)

            logging.info("%s:\n\tminimum: %f\n\tmaximum: %f\n\tmean: %f\n\tstd: %f\n",
                    description.name, minVal, maxVal, meanVal, std)

        # do a second pass to figure out how much time this log represents.
        lastTime = 0
        totalTime = 0
        sessions = 0
        for t in self.data[self.nameToDescriptionDict['Utc']]:
            if (t.timestamp - lastTime) > 60000:
                # consider time gaps of more than a minute new sessions
                sessions += 1
            else:
                totalTime += t.timestamp - lastTime

            lastTime = t.timestamp

        logging.info('a total of %d sessions were logged over %f minutes',
                sessions, totalTime/60000.)

def main():
    """a main method to call so I can use this library as a script."""
    # just set up some simple arguments so we can decide what to do
    parser = argparse.ArgumentParser(description="analyze some race capture data!")
    parser.add_argument('-m', '--merge', help='path to directory of files to merge')
    parser.add_argument('-o', '--outpath', help='path of the merged output file')
    parser.add_argument('-s', '--stats', help='print statistics on the data', action='store_true')

    args = parser.parse_args()

    merged = None

    if args.merge != '':
        logging.info('merging logs at path %s' % (args.merge))
        merged = RcpLog.loadAndMergeDirectory(args.merge)
    if args.stats and (merged is not None):
        logging.info('printing statistics for files loaded!')
        merged.printStats()
    if args.outpath:
        logging.info('writing output to new file %s' % (args.outpath))

if __name__ == "__main__":
    main()

