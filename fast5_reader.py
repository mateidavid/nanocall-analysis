#!/usr/bin/env python3

import sys

import h5py
import numpy as np


class File(object):
    """
    Class representing a Fast5 file.
    """
    raw_events_root = '/Analyses/EventDetection_000/Reads'
    basecall_log_path = '/Analyses/Basecall_2D_000/Log'
    events_path = [['/Analyses/Basecall_2D_000/BaseCalled_template/Events',
                    '/Analyses/Basecall_2D_000/BaseCalled_complement/Events'],
                    ['/Analyses/Basecall_1D_000/BaseCalled_template/Events',
                     '/Analyses/Basecall_1D_000/BaseCalled_complement/Events']]
    model_path = ['/Analyses/Basecall_2D_000/BaseCalled_template/Model',
                  '/Analyses/Basecall_2D_000/BaseCalled_complement/Model']
    model_path_path = ['/Analyses/Basecall_2D_000/Summary/basecall_1d_template',
                       '/Analyses/Basecall_2D_000/Summary/basecall_1d_complement']
    alignment_path = '/Analyses/Basecall_2D_000/BaseCalled_2D/Alignment'
    fastq_path = [['/Analyses/Basecall_2D_000/BaseCalled_template/Fastq',
                   '/Analyses/Basecall_2D_000/BaseCalled_complement/Fastq',
                   '/Analyses/Basecall_2D_000/BaseCalled_2D/Fastq'],
                  ['/Analyses/Basecall_1D_000/BaseCalled_template/Fastq',
                   '/Analyses/Basecall_1D_000/BaseCalled_complement/Fastq',
                   '/Analyses/Basecall_2D_000/BaseCalled_2D/Fastq']]
    hairpin_alignment_path = '/Analyses/Basecall_2D_000/HairpinAlign/Alignment'

    def __init__(self, file_name=None):
        self.is_open = False
        if file_name:
            self.open(file_name)

    def open(self, file_name):
        """
        Open a Fast5 file.
        """
        assert not self.is_open
        self.file = h5py.File(file_name, 'r')
        self.is_open = True
        self.chimera_version = self.get_chimaera_version()

    def close(self):
        """
        Close the Fast5 file.
        """
        assert self.is_open
        self.file.close()
        self.is_open = False

    def get_chimaera_version(self):
        """
        Get Chimaera version.
        """
        for path in ['/Analyses/Basecall_2D_000',
                     '/Analyses/Basecall_1D_000',
                     '/Analyses/Hairpin_Split_000']:
            if path not in self.file:
                continue
            _d = dict(self.file[path])
            if 'chimaera version' not in _d:
                continue
            return _d['chimaera version'].decode()

    def have_raw_events(self):
        """
        Check that the Fast5 file has a raw event sequence.
        """
        if File.raw_events_root not in self.file:
            return False
        _g = self.file[File.raw_events_root]
        return len(list(_g)) >= 1

    def get_raw_events(self):
        """
        Retrieve the raw event sequence and its attributes.
        """
        _g = self.file[File.raw_events_root]
        _r = _g[list(_g.keys())[0]]
        return _r['Events'][()], dict(_r.attrs)

    def get_ed_read_attrs(self):
        """
        Get read attributes set under EventDetection.
        """
        _g = self.file[File.raw_events_root]
        _r = _g[list(_g.keys())[0]]
        return dict(_r.attrs)

    def have_basecall_log(self):
        """
        Check that the Fast5 file has a basecalling log.
        """
        return File.basecall_log_path in self.file

    def get_basecall_log(self):
        """
        Retrieve the basecalling log.
        """
        return self.file[File.basecall_log_path][()].decode()

    def have_events(self, strand):
        """
        Check that the Fast5 file has an event sequence for the given strand.
        """
        return File.events_path[self.chimera_version >= '1.16'][strand] in self.file

    def get_events(self, strand):
        """
        Retrieve the event sequence and its attributes for the given strand.
        """
        _e = self.file[File.events_path[self.chimera_version >= '1.16'][strand]]
        _dt = np.dtype([t if 'S' not in t[1] else (t[0], t[1].replace('S', 'U'))
                        for t in _e.dtype.descr])
        return _e[()].astype(_dt), dict(_e.attrs)

    def have_model(self, strand):
        """
        Check that the Fast5 file has a model for the given strand.
        """
        return File.model_path[strand] in self.file

    def get_model(self, strand):
        """
        Retrieve the model and its attributes for the given strand.
        """
        _m = self.file[File.model_path[strand]]
        _dt = np.dtype([t if 'S' not in t[1] else (t[0], t[1].replace('S', 'U'))
                        for t in _m.dtype.descr])
        return _m[()].astype(_dt), dict(_m.attrs)

    def have_model_path(self, strand):
        """
        Check that the Fast5 file has a model path for the given strand.
        """
        return File.model_path_path[strand] in self.file and 'model_file' in dict(self.file[File.model_path_path[strand]].attrs)

    def get_model_path(self, strand):
        """
        Retrieve the model path for the given strand.
        """
        _d = dict(self.file[File.model_path_path[strand]].attrs)
        return _d['model_file'].decode()

    def have_alignment(self):
        """
        Check that the Fast5 file has a 2D alignment.
        """
        return File.alignment_path in self.file

    def get_alignment(self):
        """
        Retrieve the 2D alignment and its attributes.
        """
        _a = self.file[File.alignment_path]
        _dt = np.dtype([t if 'S' not in t[1] else (t[0], t[1].replace('S', 'U'))
                        for t in _a.dtype.descr])
        return _a[()].astype(_dt), dict(_a.attrs)

    def have_fastq(self, strand):
        """
        Check that the Fast5 file has fastq entry for the given strand (2 for 2D).
        """
        return File.fastq_path[self.chimera_version >= '1.16'][strand] in self.file

    def get_fastq(self, strand):
        """
        Retrieve the fastq entry for the given strand (2 for 2D).
        """
        return self.file[File.fastq_path[self.chimera_version >= '1.16'][strand]][()].decode()

    def have_hairpin_alignment(self):
        """
        Check that the Fast5 file has a hairpin alignment.
        """
        return File.hairpin_alignment_path in self.file

    def get_hairpin_alignment(self):
        """
        Retrieve the hairpin alignment and its attributes.
        """
        _a = self.file[File.hairpin_alignment_path]
        return _a[()], dict(_a.attrs)
