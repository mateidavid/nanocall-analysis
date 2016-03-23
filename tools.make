ifndef ROOT_DIR
$(error Do not use this makefile directly)
endif

TOOLS_TARGETS = hdf5.version python3.version bwa.version samtools.version nanocall.version

#####################
#
# HDF5
#
HDF5_URL = $(call keymap_val,software|hdf5|url)
HDF5_MD5SUM = $(call keymap_val,software|hdf5|md5sum)
HDF5_DIRNAME = $(call keymap_val,software|hdf5|dirname)
#
# download & unpack
$(eval $(call get_url,${HDF5_URL},${HDF5_MD5SUM},${SRC_DIR}/${HDF5_DIRNAME}))
# build
${TOOLS_DIR}/include/H5pubconf.h: ${SRC_DIR}/${HDF5_DIRNAME}
	cd $< && \
	./configure --prefix=${TOOLS_DIR} --disable-hl --enable-threadsafe && \
	make && \
	make install
#
# version
#
hdf5.version: ${HDF5_ROOT}/include/H5pubconf.h
	grep H5_VERSION ${HDF5_ROOT}/include/H5pubconf.h | awk '{print $$3}' | tr -d '"' >$@
#
#####################

#####################
#
# Python3 VirtualEnv
#
VIRTUALENV = virtualenv
VIRTUALENV_PYTHON3 = python3
VIRTUALENV_OPTS = 
${TOOLS_DIR}/bin/activate: ${ROOT_DIR}/requirements.txt hdf5.version
	test -f ${TOOLS_DIR}/bin/activate || ${VIRTUALENV} --python=${VIRTUALENV_PYTHON3} ${VIRTUALENV_OPTS} ${TOOLS_DIR}
	HDF5_DIR=${HDF5_ROOT} ${TOOLS_DIR}/bin/pip3 install --download-cache ${CACHE_DIR} -Ur $<
	touch ${TOOLS_DIR}/bin/activate
${TOOLS_DIR}/bin/python3: ${TOOLS_DIR}/bin/activate
python3.version: ${PYTHON3}
	${PYTHON3} --version >$@
#
#####################

#####################
#
# BWA
#
BWA_URL = $(call keymap_val,software|bwa|url)
BWA_MD5SUM = $(call keymap_val,software|bwa|md5sum)
BWA_DIRNAME = $(call keymap_val,software|bwa|dirname)
BWA_MAKE_OPTS = 
#
# download and unpack
$(eval $(call get_url,${BWA_URL},${BWA_MD5SUM},${SRC_DIR}/${BWA_DIRNAME}))
# build
${TOOLS_DIR}/bin/bwa: ${SRC_DIR}/${BWA_DIRNAME}
	cd $< && \
	make ${BWA_MAKE_OPTS} && \
	ln -sf $</bwa $@
#
# version
#
bwa.version: ${BWA}
	[ -x ${BWA} ] && ${BWA} |& grep Version | awk '{print $$2}' >$@
#
#####################

#####################
#
# Samtools
#
SAMTOOLS_URL = $(call keymap_val,software|samtools|url)
SAMTOOLS_MD5SUM = $(call keymap_val,software|samtools|md5sum)
SAMTOOLS_DIRNAME = $(call keymap_val,software|samtools|dirname)
#
# download & unpack
$(eval $(call get_url,${SAMTOOLS_URL},${SAMTOOLS_MD5SUM},${SRC_DIR}/${SAMTOOLS_DIRNAME}))
# build
${TOOLS_DIR}/bin/samtools: ${SRC_DIR}/${SAMTOOLS_DIRNAME}
	cd $< && \
	make && \
	make prefix=${TOOLS_DIR} install
#
# version
#
samtools.version: ${SAMTOOLS}
	[ -x ${SAMTOOLS} ] && ${SAMTOOLS} --version >$@
#
#####################

#####################
#
# Nanocall
#
NANOCALL_DIR = ${SRC_DIR}/nanocall
NANOCALL_BUILD_DIR = ${NANOCALL_DIR}/build
NANOCALL_GIT = $(call keymap_val,software|nanocall|url)
NANOCALL_CMAKE_OPTS = -DHDF5_ROOT=${HDF5_ROOT}
NANOCALL_MAKE_OPTS =
#
# download
#
${NANOCALL_DIR}/src/CMakeLists.txt:
	git clone --recursive ${NANOCALL_GIT} ${NANOCALL_DIR}
#
# build (default)
#
${TOOLS_DIR}/bin/nanocall: ${NANOCALL_DIR}/src/CMakeLists.txt hdf5.version
	mkdir -p ${NANOCALL_BUILD_DIR} && \
	cd ${NANOCALL_BUILD_DIR} && \
	cmake ${NANOCALL_DIR}/src -DCMAKE_INSTALL_PREFIX=${TOOLS_DIR} ${NANOCALL_CMAKE_OPTS} && \
	make ${NANOCALL_MAKE_OPTS} && \
	make install
#
# version
#
nanocall.version: ${NANOCALL}
	${NANOCALL} --version | awk 'NR==2 {print $$3}' >$@
#
#####################
