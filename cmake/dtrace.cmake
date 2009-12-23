# Copyright (C) 2009 Sun Microsystems, Inc
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA 

# Check if OS supports DTrace
MACRO(CHECK_DTRACE)
 FIND_PROGRAM(DTRACE dtrace)
 MARK_AS_ADVANCED(DTRACE)

 # On FreeBSD, dtrace does not handle userland tracing yet
 IF(DTRACE AND NOT CMAKE_SYSTEM_NAME MATCHES "FreeBSD")
   SET(ENABLE_DTRACE ON CACHE BOOL "Enable dtrace")
 ENDIF()
 SET(HAVE_DTRACE ${ENABLE_DTRACE})
 IF(CMAKE_SYSTEM_NAME MATCHES "SunOS")
   IF(CMAKE_SIZEOF_VOID_P EQUAL 4)
     SET(DTRACE_FLAGS -32 CACHE INTERNAL "DTrace architecture flags")
   ELSE()
     SET(DTRACE_FLAGS -64 CACHE INTERNAL "DTrace architecture flags")
   ENDIF()
 ENDIF()
ENDMACRO()

CHECK_DTRACE()

# Produce a header file  with
# DTrace macros
MACRO (DTRACE_HEADER provider header header_no_dtrace)
 IF(ENABLE_DTRACE)
 ADD_CUSTOM_COMMAND(
   OUTPUT  ${header} ${header_no_dtrace}
   COMMAND ${DTRACE} -h -s ${provider} -o ${header}
	 COMMAND perl ${CMAKE_SOURCE_DIR}/scripts/dheadgen.pl -f ${provider} > ${header_no_dtrace}
   DEPENDS ${provider}
 )
 ENDIF()
ENDMACRO()


# Create provider headers
IF(ENABLE_DTRACE)
  CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/include/probes_mysql.d.base 
    ${CMAKE_BINARY_DIR}/include/probes_mysql.d COPYONLY)
  DTRACE_HEADER(
   ${CMAKE_BINARY_DIR}/include/probes_mysql.d 
   ${CMAKE_BINARY_DIR}/include/probes_mysql_dtrace.h
   ${CMAKE_BINARY_DIR}/include/probes_mysql_nodtrace.h
  )
  ADD_CUSTOM_TARGET(gen_dtrace_header
  DEPENDS  
  ${CMAKE_BINARY_DIR}/include/probes_mysql.d
  ${CMAKE_BINARY_DIR}/include/probes_mysql_dtrace.h
  ${CMAKE_BINARY_DIR}/include/probes_mysql_nodtrace.h
  ) 
ENDIF()


MACRO (DTRACE_INSTRUMENT target)
  IF(ENABLE_DTRACE)
    ADD_DEPENDENCIES(${target} gen_dtrace_header)

     # On Solaris, invoke dtrace -G to generate object file and
     # link it together with target.
    IF(CMAKE_SYSTEM_NAME MATCHES "SunOS")
      SET(objdir ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${target}.dir)
      SET(outfile ${objdir}/${target}_dtrace.o)
      GET_TARGET_PROPERTY(target_type ${target} TYPE)
      ADD_CUSTOM_COMMAND(
        TARGET ${target} PRE_LINK 
        COMMAND ${CMAKE_COMMAND}
          -DDTRACE=${DTRACE}	  
          -DOUTFILE=${outfile} 
          -DDFILE=${CMAKE_BINARY_DIR}/include/probes_mysql.d
          -DDTRACE_FLAGS=${DTRACE_FLAGS}
          -DDIRS=.
          -DTYPE=${target_type}
          -P ${CMAKE_SOURCE_DIR}/cmake/dtrace_prelink.cmake
        WORKING_DIRECTORY ${objdir}
      )
      # Add full  object path to linker flags
      GET_TARGET_PROPERTY(target_type ${target} TYPE)
      IF(NOT target_type MATCHES "STATIC")
        SET_TARGET_PROPERTIES(${target} PROPERTIES LINK_FLAGS "${outfile}")
      ELSE()
        # For static library flags, add the object to the library.
        # Note: DTrace probes in static libraries are  unusable currently 
        # (see explanation for DTRACE_INSTRUMENT_STATIC_LIBS below)
        # but maybe one day this will be fixed.
        GET_TARGET_PROPERTY(target_location ${target} LOCATION)
        ADD_CUSTOM_COMMAND(
         TARGET ${target} POST_BUILD
         COMMAND ${CMAKE_AR} r  ${target_location} ${outfile}
	 COMMAND ${CMAKE_RANLIB} ${target_location}
        )
       # Used in DTRACE_INSTRUMENT_WITH_STATIC_LIBS
       SET(TARGET_OBJECT_DIRECTORY_${target}  ${objdir} CACHE INTERNAL "")
      ENDIF()
    ENDIF()
  ENDIF()
ENDMACRO()


# Ugly workaround for Solaris' DTrace inability to use probes
# from static libraries, discussed e.g in this thread
# (http://opensolaris.org/jive/thread.jspa?messageID=432454)
# We have to collect all object files that may be instrumented
# and go into the mysqld (also those that come from in static libs)
# run them again through dtrace -G to generate an ELF file that links
# to mysqld.
MACRO (DTRACE_INSTRUMENT_STATIC_LIBS target libs)
IF(CMAKE_SYSTEM_NAME MATCHES "SunOS" AND ENABLE_DTRACE)
  FOREACH(lib ${libs})
    SET(dirs ${dirs} ${TARGET_OBJECT_DIRECTORY_${lib}})
  ENDFOREACH()
  SET (obj ${CMAKE_CURRENT_BINARY_DIR}/${target}_dtrace_all.o)
  ADD_CUSTOM_COMMAND(
  OUTPUT ${obj}
  DEPENDS ${libs}
  COMMAND ${CMAKE_COMMAND}
   -DDTRACE=${DTRACE}	  
   -DOUTFILE=${obj} 
   -DDFILE=${CMAKE_BINARY_DIR}/include/probes_mysql.d
   -DDTRACE_FLAGS=${DTRACE_FLAGS}
   "-DDIRS=${dirs}"
   -DTYPE=MERGE
   -P ${CMAKE_SOURCE_DIR}/cmake/dtrace_prelink.cmake
   VERBATIM
  )
  ADD_CUSTOM_TARGET(${target}_dtrace_all  DEPENDS ${obj})
  ADD_DEPENDENCIES(${target} ${target}_dtrace_all)
  TARGET_LINK_LIBRARIES(${target} ${obj})
ENDIF()
ENDMACRO()