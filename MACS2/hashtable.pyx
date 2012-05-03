"""
Modified from Pandas: https://github.com/pydata/pandas/blob/master/pandas/src/hashtable.pyx
"""

from khash cimport *
from numpy cimport *
import numpy as np
cimport numpy as np

cdef inline bint _checknan(object val):
    return not np.PyArray_Check(val) and val != val

def list_to_object_array(list obj):
    """
    Convert list to object ndarray. Seriously can't believe I had to write this
    function
    """
    cdef:
        Py_ssize_t i, n
        ndarray[object] arr

    n = len(obj)
    arr = np.empty(n, dtype=object)

    for i from 0 <= i < n:
        arr[i] = obj[i]

    return arr


def obj_unique(ndarray[object] arr):
    cdef:
        kh_pyset_t *table
        # PyObject *obj
        object obj
        PyObject **data
        int ret = 0
        khiter_t k
        Py_ssize_t i, n
        list uniques

    n = len(arr)
    uniques = []

    table = kh_init_pyset()

    data = <PyObject**> arr.data

    # size hint
    kh_resize_pyset(table, n // 10)

    for i in range(n):
        obj = arr[i]

        k = kh_get_pyset(table, <PyObject*> obj)
        if not kh_exist_pyset(table, k):
            k = kh_put_pyset(table, <PyObject*> obj, &ret)
            # uniques.append(obj)
            # Py_INCREF(<object> obj)

    kh_destroy_pyset(table)

    return None

def int64_unique(ndarray[int64_t] arr):
    cdef:
        kh_int64_t *table
        # PyObject *obj
        int64_t obj
        PyObject **data
        int ret = 0
        khiter_t k
        Py_ssize_t i, j, n
        ndarray[int64_t] uniques

    n = len(arr)
    uniques = np.empty(n, dtype='i8')

    table = kh_init_int64()
    kh_resize_int64(table, n)

    j = 0

    for i in range(n):
        obj = arr[i]

        k = kh_get_int64(table, obj)
        if not kh_exist_int64(table, k):
            k = kh_put_int64(table, obj, &ret)
            uniques[j] = obj
            j += 1
            # Py_INCREF(<object> obj)

    kh_destroy_int64(table)

    return np.sort(uniques[:j])

cdef class Int64HashTable:

    cdef:
        kh_int64_t *table

    def __init__(self, size_hint=1):
        if size_hint is not None:
            kh_resize_int64(self.table, size_hint)

    def __cinit__(self):
        self.table = kh_init_int64()

    def __dealloc__(self):
        kh_destroy_int64(self.table)

    cpdef bint has_key(self, int64_t val):
        cdef khiter_t k
        k = kh_get_int64(self.table, val)
        return k != self.table.n_buckets

    cpdef get_item(self, int64_t val):
        cdef khiter_t k
        k = kh_get_int64(self.table, val)
        if k != self.table.n_buckets:
            return self.table.vals[k]
        else:
            raise KeyError(val)

    def get_iter_test(self, int64_t key, Py_ssize_t iterations):
        cdef Py_ssize_t i, val=0
        for i in range(iterations):
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                val = self.table.vals[k]

    cpdef set_item(self, int64_t key, Py_ssize_t val):
        cdef:
            khiter_t k
            int ret = 0

        k = kh_put_int64(self.table, key, &ret)
        self.table.keys[k] = key
        if kh_exist_int64(self.table, k):
            self.table.vals[k] = val
        else:
            raise KeyError(key)

    def map(self, ndarray[int64_t] keys, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            int64_t key
            khiter_t k

        for i in range(n):
            key = keys[i]
            k = kh_put_int64(self.table, key, &ret)
            self.table.vals[k] = <Py_ssize_t> values[i]

    def map_locations(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            int64_t val
            khiter_t k

        for i in range(n):
            val = values[i]
            k = kh_put_int64(self.table, val, &ret)
            self.table.vals[k] = i

    def lookup(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            int64_t val
            khiter_t k
            ndarray[int64_t] locs = np.empty(n, dtype='i8')

        for i in range(n):
            val = values[i]
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def lookup_i4(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            int64_t val
            khiter_t k
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        for i in range(n):
            val = values[i]
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def factorize(self, ndarray[object] values):
        reverse = {}
        labels, counts = self.get_labels(values, reverse, 0)
        return reverse, labels, counts

    def get_labels(self, ndarray[int64_t] values, list uniques,
                   Py_ssize_t count_prior, Py_ssize_t na_sentinel):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = count_prior
            int ret = 0
            int64_t val
            khiter_t k

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count_prior + n, dtype=np.int32)

        for i in range(n):
            val = values[i]
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_int64(self.table, val, &ret)
                self.table.vals[k] = count
                uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

    def get_labels_groupby(self, ndarray[int64_t] values, list uniques):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            Py_ssize_t idx, count = 0
            int ret = 0
            int64_t val
            khiter_t k

        labels = np.empty(n, dtype=np.int32)

        for i in range(n):
            val = values[i]

            # specific for groupby
            if val < 0:
                labels[i] = -1
                continue

            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
            else:
                k = kh_put_int64(self.table, val, &ret)
                self.table.vals[k] = count
                uniques.append(val)
                labels[i] = count
                count += 1

        return labels

    def unique(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            Py_ssize_t idx, count = 0
            int ret = 0
            int64_t val
            khiter_t k
            list uniques = []

        # TODO: kvec

        for i in range(n):
            val = values[i]
            k = kh_get_int64(self.table, val)
            if k == self.table.n_buckets:
                k = kh_put_int64(self.table, val, &ret)
                uniques.append(val)
                count += 1

        return uniques

def value_count_int64(ndarray[int64_t] values):
    cdef:
        Py_ssize_t i, n = len(values)
        kh_int64_t *table
        int ret = 0
        list uniques = []

    table = kh_init_int64()
    kh_resize_int64(table, n)

    for i in range(n):
        val = values[i]
        k = kh_get_int64(table, val)
        if k != table.n_buckets:
            table.vals[k] += 1
        else:
            k = kh_put_int64(table, val, &ret)
            table.vals[k] = 1

    # for (k = kh_begin(h); k != kh_end(h); ++k)
    # 	if (kh_exist(h, k)) kh_value(h, k) = 1;
    i = 0
    result_keys = np.empty(table.n_occupied, dtype=np.int64)
    result_counts = np.zeros(table.n_occupied, dtype=np.int64)
    for k in range(table.n_buckets):
        if kh_exist_int64(table, k):
            result_keys[i] = table.keys[k]
            result_counts[i] = table.vals[k]
            i += 1
    kh_destroy_int64(table)

    return result_keys, result_counts

ONAN = np.nan

cdef class Float64HashTable:

    cdef:
        kh_float64_t *table

    def __init__(self, size_hint=1):
        if size_hint is not None:
            kh_resize_float64(self.table, size_hint)

    def __cinit__(self):
        self.table = kh_init_float64()

    def __dealloc__(self):
        kh_destroy_float64(self.table)

    def factorize(self, ndarray[float64_t] values):
        uniques = []
        labels, counts = self.get_labels(values, uniques, 0, -1)
        return uniques, labels, counts

    cpdef get_labels(self, ndarray[float64_t] values, list uniques,
                     Py_ssize_t count_prior, int32_t na_sentinel):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = count_prior
            int ret = 0
            float64_t val
            khiter_t k

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count_prior + n, dtype=np.int32)

        for i in range(n):
            val = values[i]

            if val != val:
                labels[i] = na_sentinel
                continue

            k = kh_get_float64(self.table, val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_float64(self.table, val, &ret)
                self.table.vals[k] = count
                uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

    def map_locations(self, ndarray[float64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            khiter_t k

        for i in range(n):
            k = kh_put_float64(self.table, values[i], &ret)
            self.table.vals[k] = i

    def lookup(self, ndarray[float64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            float64_t val
            khiter_t k
            ndarray[int32_t] locs = np.empty(n, dtype=np.int32)

        for i in range(n):
            val = values[i]
            k = kh_get_float64(self.table, val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def unique(self, ndarray[float64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            Py_ssize_t idx, count = 0
            int ret = 0
            float64_t val
            khiter_t k
            list uniques = []
            bint seen_na = 0

        # TODO: kvec

        for i in range(n):
            val = values[i]

            if val == val:
                k = kh_get_float64(self.table, val)
                if k == self.table.n_buckets:
                    k = kh_put_float64(self.table, val, &ret)
                    uniques.append(val)
                    count += 1
            elif not seen_na:
                seen_na = 1
                uniques.append(ONAN)

        return uniques

cdef class PyObjectHashTable:

    cdef:
        kh_pymap_t *table

    def __init__(self, size_hint=1):
        self.table = kh_init_pymap()
        kh_resize_pymap(self.table, size_hint)

    def __dealloc__(self):
        if self.table is not NULL:
            self.destroy()

    cpdef destroy(self):
        kh_destroy_pymap(self.table)
        self.table = NULL

    cpdef get_item(self, object val):
        cdef khiter_t k
        k = kh_get_pymap(self.table, <PyObject*>val)
        if k != self.table.n_buckets:
            return self.table.vals[k]
        else:
            raise KeyError(val)

    def get_iter_test(self, object key, Py_ssize_t iterations):
        cdef Py_ssize_t i, val
        for i in range(iterations):
            k = kh_get_pymap(self.table, <PyObject*>key)
            if k != self.table.n_buckets:
                val = self.table.vals[k]

    cpdef set_item(self, object key, Py_ssize_t val):
        cdef:
            khiter_t k
            int ret = 0
            char* buf

        k = kh_put_pymap(self.table, <PyObject*>key, &ret)
        # self.table.keys[k] = key
        if kh_exist_pymap(self.table, k):
            self.table.vals[k] = val
        else:
            raise KeyError(key)

    def map_locations(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            object val
            khiter_t k

        for i in range(n):
            val = values[i]
            k = kh_put_pymap(self.table, <PyObject*>val, &ret)
            self.table.vals[k] = i

    def lookup(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            object val
            khiter_t k
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        for i in range(n):
            val = values[i]
            k = kh_get_pymap(self.table, <PyObject*>val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def lookup2(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret = 0
            object val
            khiter_t k
            long hval
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        # for i in range(n):
        #     val = values[i]
            # hval = PyObject_Hash(val)
            # k = kh_get_pymap(self.table, <PyObject*>val)

        return locs

    def unique(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            Py_ssize_t idx, count = 0
            int ret = 0
            object val
            khiter_t k
            list uniques = []
            bint seen_na = 0

        for i in range(n):
            val = values[i]

            if not _checknan(val):
                k = kh_get_pymap(self.table, <PyObject*>val)
                if k == self.table.n_buckets:
                    k = kh_put_pymap(self.table, <PyObject*>val, &ret)
                    uniques.append(val)
            elif not seen_na:
                seen_na = 1
                uniques.append(ONAN)

        return uniques

    cpdef get_labels(self, ndarray[object] values, list uniques,
                     Py_ssize_t count_prior, int32_t na_sentinel):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = count_prior
            int ret = 0
            object val
            khiter_t k

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count_prior + n, dtype=np.int32)

        for i in range(n):
            val = values[i]

            if val != val or val is None:
                labels[i] = na_sentinel
                continue

            k = kh_get_pymap(self.table, <PyObject*>val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_pymap(self.table, <PyObject*>val, &ret)
                self.table.vals[k] = count
                uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

    # def unique(self, ndarray[object] values, list uniques):
    #     cdef:
    #         Py_ssize_t i, n = len(values)
    #         Py_ssize_t idx, count = 0
    #         int ret
    #         object val
    #         khiter_t k

    #     for i in range(n):
    #         val = values[i]
    #         k = kh_get_pymap(self.table, <PyObject*>val)
    #         if k == self.table.n_buckets:
    #             k = kh_put_pymap(self.table, <PyObject*>val, &ret)
    #             uniques.append(val)
    #             count += 1

cdef class Factorizer:

    cdef public:
        PyObjectHashTable table
        list uniques
        Py_ssize_t count

    def __init__(self, size_hint):
        self.table = PyObjectHashTable(size_hint)
        self.uniques = []
        self.count = 0

    def get_count(self):
        return self.count

    def factorize(self, ndarray[object] values, sort=False, na_sentinel=-1):
        labels, counts = self.table.get_labels(values, self.uniques,
                                               self.count, na_sentinel)

        # sort on
        if sort:
            sorter = list_to_object_array(self.uniques).argsort()
            reverse_indexer = np.empty(len(sorter), dtype=np.int32)
            reverse_indexer.put(sorter, np.arange(len(sorter)))

            labels = reverse_indexer.take(labels)
            counts = counts.take(sorter)

        self.count = len(counts)
        return labels, counts

    def unique(self, ndarray[object] values):
        # just for fun
        return self.table.unique(values)

cdef class Int64Factorizer:

    cdef public:
        Int64HashTable table
        list uniques
        Py_ssize_t count

    def __init__(self, size_hint):
        self.table = Int64HashTable(size_hint)
        self.uniques = []
        self.count = 0

    def get_count(self):
        return self.count

    def factorize(self, ndarray[int64_t] values, sort=False):
        labels, counts = self.table.get_labels(values, self.uniques,
                                               self.count, -1)

        # sort on
        if sort:
            sorter = list_to_object_array(self.uniques).argsort()
            reverse_indexer = np.empty(len(sorter), dtype=np.int32)
            reverse_indexer.put(sorter, np.arange(len(sorter)))

            labels = reverse_indexer.take(labels)
            counts = counts.take(sorter)

        self.count = len(counts)
        return labels, counts

cdef class DictFactorizer:

    cdef public:
        dict table
        list uniques
        Py_ssize_t count

    def __init__(self, table=None, uniques=None):
        if table is None:
            self.table = {}
        else:
            self.table = table

        if uniques is None:
            self.uniques = []
            self.count = 0
        else:
            self.uniques = uniques
            self.count = len(uniques)

    def get_count(self):
        return self.count

    def get_labels(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = self.count
            int ret = 0
            object val

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count + n, dtype=np.int32)

        for i in range(n):
            val = values[i]

            if val in self.table:
                idx = self.table[val]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                self.table[val] = count
                self.uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

    def factorize(self, ndarray[object] values, sort=False):
        labels, counts = self.get_labels(values)

        # sort on
        if sort:
            sorter = list_to_object_array(self.uniques).argsort()
            reverse_indexer = np.empty(len(sorter), dtype=np.int32)
            reverse_indexer.put(sorter, np.arange(len(sorter)))

            labels = reverse_indexer.take(labels)
            counts = counts.take(sorter)

        self.count = len(counts)
        return labels, counts

    def unique(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            Py_ssize_t idx, count = self.count
            object val

        for i in range(n):
            val = values[i]
            if val not in self.table:
                self.table[val] = count
                self.uniques.append(val)
                count += 1
        return self.uniques


    def unique_int64(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            Py_ssize_t idx, count = self.count
            int64_t val

        for i in range(n):
            val = values[i]
            if val not in self.table:
                self.table[val] = count
                self.uniques.append(val)
                count += 1
        return self.uniques

def lookup2(ndarray[object] values):
    cdef:
        Py_ssize_t i, n = len(values)
        int ret = 0
        object val
        khiter_t k
        long hval
        ndarray[int32_t] locs = np.empty(n, dtype='i4')

    # for i in range(n):
    #     val = values[i]
        # hval = PyObject_Hash(val)
        # k = kh_get_pymap(self.table, <PyObject*>val)

    return locs

