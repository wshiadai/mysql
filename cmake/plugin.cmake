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


GET_FILENAME_COMPONENT(MYSQL_CMAKE_SCRIPT_DIR ${CMAKE_CURRENT_LIST_FILE} PATH)
INCLUDE(${MYSQL_CMAKE_SCRIPT_DIR}/cmake_parse_arguments.cmake)

# MYSQL_ADD_PLUGIN(plugin_name source1...sourceN
# [STORAGE_ENGINE]
# [MANDATORY|DEFAULT]
# [STATIC_ONLY|DYNAMIC_ONLY]
# [MODULE_OUTPUT_NAME module_name]
# [STATIC_OUTPUT_NAME static_name]
# [RECOMPILE_FOR_EMBEDDED]
# [LINK_LIBRARIES lib1...libN]
# [DEPENDENCIES target1...targetN]

MACRO(MYSQL_ADD_PLUGIN)
  CMAKE_PARSE_ARGUMENTS(ARG
    "LINK_LIBRARIES;DEPENDENCIES;MODULE_OUTPUT_NAME;STATIC_OUTPUT_NAME"
    "STORAGE_ENGINE;STATIC_ONLY;MODULE_ONLY;MANDATORY;DEFAULT;DISABLED;RECOMPILE_FOR_EMBEDDED"
    ${ARGN}
  )
  
  # Add common include directories
  INCLUDE_DIRECTORIES(${CMAKE_SOURCE_DIR}/include 
                    ${CMAKE_SOURCE_DIR}/sql
                    ${CMAKE_SOURCE_DIR}/regex
                    ${SSL_INCLUDE_DIRS}
                    ${ZLIB_INCLUDE_DIR})

  LIST(GET ARG_DEFAULT_ARGS 0 plugin) 
  SET(SOURCES ${ARG_DEFAULT_ARGS})
  LIST(REMOVE_AT SOURCES 0)
  STRING(TOUPPER ${plugin} plugin)
  STRING(TOLOWER ${plugin} target)
  
  # Figure out whether to build plugin
  IF(WITH_PLUGIN_${plugin})
    SET(WITH_${plugin} 1)
  ENDIF()

  IF(WITH_${plugin}_STORAGE_ENGINE 
    OR WITH_{$plugin}
    OR WITH_ALL 
    OR WITH_MAX 
    OR ARG_DEFAULT 
    AND NOT WITHOUT_${plugin}_STORAGE_ENGINE
    AND NOT WITHOUT_${plugin}
    AND NOT ARG_MODULE_ONLY)
     
    SET(WITH_${plugin} 1)
  ELSEIF(WITHOUT_${plugin}_STORAGE_ENGINE OR WITH_NONE OR ${plugin}_DISABLED)
    SET(WITHOUT_${plugin} 1)
    SET(WITH_${plugin}_STORAGE_ENGINE 0)
    SET(WITH_${plugin} 0)
  ENDIF()
  
  
  IF(ARG_MANDATORY)
    SET(WITH_${plugin} 1)
  ENDIF()

  
  IF(ARG_STORAGE_ENGINE)
    SET(with_var "WITH_${plugin}_STORAGE_ENGINE" )
  ELSE()
    SET(with_var "WITH_${plugin}")
  ENDIF()
  
  IF(NOT ARG_DEPENDENCIES)
    SET(ARG_DEPENDENCIES)
  ENDIF()
  # Build either static library or module
  IF (WITH_${plugin} AND NOT ARG_MODULE_ONLY)
    ADD_LIBRARY(${target} STATIC ${SOURCES})
    SET_TARGET_PROPERTIES(${target} PROPERTIES COMPILE_DEFINITONS "MYSQL_SERVER")
    DTRACE_INSTRUMENT(${target})
    ADD_DEPENDENCIES(${target} GenError ${ARG_DEPENDENCIES})
    IF(WITH_EMBEDDED_SERVER)
      # Embedded library should contain PIC code and be linkable
      # to shared libraries (on systems that need PIC)
      IF(ARG_RECOMPILE_FOR_EMBEDDED OR NOT _SKIP_PIC)
        # Recompile some plugins for embedded
        ADD_CONVENIENCE_LIBRARY(${target}_embedded ${SOURCES})
        DTRACE_INSTRUMENT(${target}_embedded)   
        IF(ARG_RECOMPILE_FOR_EMBEDDED)
          SET_TARGET_PROPERTIES(${target}_embedded 
            PROPERTIES COMPILE_DEFINITIONS "MYSQL_SERVER;EMBEDDED_LIBRARY")
        ENDIF()
        ADD_DEPENDENCIES(${target}_embedded GenError)
      ENDIF()
    ENDIF()
    
    IF(ARG_STATIC_OUTPUT_NAME)
      SET_TARGET_PROPERTIES(${target} PROPERTIES 
      OUTPUT_NAME ${ARG_STATIC_OUTPUT_NAME})
    ENDIF()

    # Update mysqld dependencies
    SET (MYSQLD_STATIC_PLUGIN_LIBS ${MYSQLD_STATIC_PLUGIN_LIBS} 
      ${target} CACHE INTERNAL "")

    SET (mysql_plugin_defs  "${mysql_plugin_defs},builtin_${target}_plugin" 
      PARENT_SCOPE)
    IF(ARG_STORAGE_ENGINE)
      SET(${with_var} ON CACHE BOOL "Link ${plugin} statically to the server" 
        FORCE)
    ENDIF()
  ELSEIF(NOT WITHOUT_${plugin} AND NOT ARG_STATIC_ONLY  AND NOT WITHOUT_DYNAMIC_PLUGINS)
     
    ADD_LIBRARY(${target} MODULE ${SOURCES})  
    DTRACE_INSTRUMENT(${target})
    SET_TARGET_PROPERTIES (${target} PROPERTIES PREFIX ""
      COMPILE_DEFINITIONS "MYSQL_DYNAMIC_PLUGIN")
    IF(ARG_LINK_LIBRARIES)
      TARGET_LINK_LIBRARIES (${target} ${ARG_LINK_LIBRARIES})
    ENDIF()
    TARGET_LINK_LIBRARIES (${target} mysqlservices)

    # Plugin uses symbols defined in mysqld executable.
    # Some operating systems like Windows and OSX and are pretty strict about 
    # unresolved symbols. Others are less strict and allow unresolved symbols
    # in shared libraries. On Linux for example, CMake does not even add 
    # executable to the linker command line (it would result into link error). 
    # Thus we skip TARGET_LINK_LIBRARIES on Linux, as it would only generate
    # an additional dependency.
    IF(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
      TARGET_LINK_LIBRARIES (${target} mysqld ${ARG_LINK_LIBRARIES})
    ENDIF()
    ADD_DEPENDENCIES(${target} GenError ${ARG_DEPENDENCIES})

    IF(NOT ARG_MODULE_OUTPUT_NAME)
      IF(ARG_STORAGE_ENGINE)
        SET(ARG_MODULE_OUTPUT_NAME "ha_${target}")
      ELSE()
        SET(ARG_MODULE_OUTPUT_NAME "${target}")
      ENDIF()
    ENDIF()
    SET_TARGET_PROPERTIES(${target} PROPERTIES 
      OUTPUT_NAME "${ARG_MODULE_OUTPUT_NAME}")  
    # Install dynamic library
    SET(INSTALL_LOCATION lib/plugin)
    MYSQL_INSTALL_TARGETS(${target} DESTINATION ${INSTALL_LOCATION})
  ENDIF()
ENDMACRO()


# Add all CMake projects under storage  and plugin 
# subdirectories, configure sql_builtins.cc
MACRO(CONFIGURE_PLUGINS)
  FILE(GLOB dirs_storage ${CMAKE_SOURCE_DIR}/storage/*)
  FILE(GLOB dirs_plugin ${CMAKE_SOURCE_DIR}/plugin/*)
  FOREACH(dir ${dirs_storage} ${dirs_plugin})
    IF (EXISTS ${dir}/CMakeLists.txt)
      ADD_SUBDIRECTORY(${dir})
    ENDIF()
  ENDFOREACH()
ENDMACRO()