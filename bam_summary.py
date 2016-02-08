import numpy as np

def load_data(in_f):
    _d = np.genfromtxt(in_f.buffer, names=True, dtype=None)
    _d.sort(order=['read_name'])
    return _d

def _interval_intersect(a, b):
    return (a[0] <= b[0] and b[0] < a[1]) or (b[0] <= a[0] and a[0] < b[1])

def _align_pos(e):
    return (e['align_pos'], e['align_pos'] + e['align_len'])

def align_overlap(e1, e2):
    return e1['align_chr'] == e2['align_chr'] and _interval_intersect(_align_pos(e1), _align_pos(e2))

