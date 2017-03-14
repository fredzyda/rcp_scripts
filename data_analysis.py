#/usr/bin/python

# a script for analyzing RCP data. the goal here is to do things like look at long
# term trends over multiple races.

import csv
import collections
import logging

# set log level
logging.basicConfig(level=logging.INFO)

class RcpLog:
    """this class represents an RCP log file.
    """
    def __init__(self, filename=None):
        """the constructor. load the file if one was specified, otherwise set everything
           to null.
        """
        # setup all the instance fields
        self.filename = filename
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
        with open(self.filename, 'r') as f:
            reader = csv.reader(f)
            self.rawlines = [line for line in reader]
            logging.info("read %d lines", len(self.rawlines))
            self.parseRawlines()

    def parseRawlines(self):
        """this method is kind of part of load, but it also makes it way easier
           to merge files and then reparse the resulting concatenated rawlines
        """
        # the file always begins with the header line
        self.headerLine = self.rawlines[0]

        # make sure to reset the descriptions and data members. this becomes important
        # when we start merging files together
        self.descriptions = []
        self.data = {}
        self.nameToDescriptionDict = {}

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

        # now parse all the raw data into DataPoints
        for line in self.rawlines[1:]:
            # UTC time in milliseconds is always the second entry
            # I think it is sort of safe to assume that...
            timestamp = int(line[1])

            for i in range(len(self.descriptions)):
                if line[i] != '':
                    # many fields are empty because some sensors log at way higher
                    # rates than others. we only care about the data that's actually there.
                    # I'm also assuming everything is a float for now...
                    self.data[self.descriptions[i]].append(
                            self.DataPoint(timestamp=timestamp, value=float(line[i])))

        # fire off a quick logging message about what we just loaded.
        for description in self.descriptions:
            logging.info("Parsed %d %s records", len(self.data[description]), description.name)
