include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(ProjectManagement_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(ProjectManagement_setup_options)
  option(ProjectManagement_ENABLE_HARDENING "Enable hardening" ON)
  option(ProjectManagement_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    ProjectManagement_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    ProjectManagement_ENABLE_HARDENING
    OFF)

  ProjectManagement_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR ProjectManagement_PACKAGING_MAINTAINER_MODE)
    option(ProjectManagement_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(ProjectManagement_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(ProjectManagement_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(ProjectManagement_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(ProjectManagement_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(ProjectManagement_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(ProjectManagement_ENABLE_PCH "Enable precompiled headers" OFF)
    option(ProjectManagement_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(ProjectManagement_ENABLE_IPO "Enable IPO/LTO" ON)
    option(ProjectManagement_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(ProjectManagement_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(ProjectManagement_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(ProjectManagement_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(ProjectManagement_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(ProjectManagement_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(ProjectManagement_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(ProjectManagement_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(ProjectManagement_ENABLE_PCH "Enable precompiled headers" OFF)
    option(ProjectManagement_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      ProjectManagement_ENABLE_IPO
      ProjectManagement_WARNINGS_AS_ERRORS
      ProjectManagement_ENABLE_USER_LINKER
      ProjectManagement_ENABLE_SANITIZER_ADDRESS
      ProjectManagement_ENABLE_SANITIZER_LEAK
      ProjectManagement_ENABLE_SANITIZER_UNDEFINED
      ProjectManagement_ENABLE_SANITIZER_THREAD
      ProjectManagement_ENABLE_SANITIZER_MEMORY
      ProjectManagement_ENABLE_UNITY_BUILD
      ProjectManagement_ENABLE_CLANG_TIDY
      ProjectManagement_ENABLE_CPPCHECK
      ProjectManagement_ENABLE_COVERAGE
      ProjectManagement_ENABLE_PCH
      ProjectManagement_ENABLE_CACHE)
  endif()

  ProjectManagement_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (ProjectManagement_ENABLE_SANITIZER_ADDRESS OR ProjectManagement_ENABLE_SANITIZER_THREAD OR ProjectManagement_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(ProjectManagement_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(ProjectManagement_global_options)
  if(ProjectManagement_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    ProjectManagement_enable_ipo()
  endif()

  ProjectManagement_supports_sanitizers()

  if(ProjectManagement_ENABLE_HARDENING AND ProjectManagement_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR ProjectManagement_ENABLE_SANITIZER_UNDEFINED
       OR ProjectManagement_ENABLE_SANITIZER_ADDRESS
       OR ProjectManagement_ENABLE_SANITIZER_THREAD
       OR ProjectManagement_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${ProjectManagement_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${ProjectManagement_ENABLE_SANITIZER_UNDEFINED}")
    ProjectManagement_enable_hardening(ProjectManagement_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(ProjectManagement_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(ProjectManagement_warnings INTERFACE)
  add_library(ProjectManagement_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  ProjectManagement_set_project_warnings(
    ProjectManagement_warnings
    ${ProjectManagement_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(ProjectManagement_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    ProjectManagement_configure_linker(ProjectManagement_options)
  endif()

  include(cmake/Sanitizers.cmake)
  ProjectManagement_enable_sanitizers(
    ProjectManagement_options
    ${ProjectManagement_ENABLE_SANITIZER_ADDRESS}
    ${ProjectManagement_ENABLE_SANITIZER_LEAK}
    ${ProjectManagement_ENABLE_SANITIZER_UNDEFINED}
    ${ProjectManagement_ENABLE_SANITIZER_THREAD}
    ${ProjectManagement_ENABLE_SANITIZER_MEMORY})

  set_target_properties(ProjectManagement_options PROPERTIES UNITY_BUILD ${ProjectManagement_ENABLE_UNITY_BUILD})

  if(ProjectManagement_ENABLE_PCH)
    target_precompile_headers(
      ProjectManagement_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(ProjectManagement_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    ProjectManagement_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(ProjectManagement_ENABLE_CLANG_TIDY)
    ProjectManagement_enable_clang_tidy(ProjectManagement_options ${ProjectManagement_WARNINGS_AS_ERRORS})
  endif()

  if(ProjectManagement_ENABLE_CPPCHECK)
    ProjectManagement_enable_cppcheck(${ProjectManagement_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(ProjectManagement_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    ProjectManagement_enable_coverage(ProjectManagement_options)
  endif()

  if(ProjectManagement_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(ProjectManagement_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(ProjectManagement_ENABLE_HARDENING AND NOT ProjectManagement_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR ProjectManagement_ENABLE_SANITIZER_UNDEFINED
       OR ProjectManagement_ENABLE_SANITIZER_ADDRESS
       OR ProjectManagement_ENABLE_SANITIZER_THREAD
       OR ProjectManagement_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    ProjectManagement_enable_hardening(ProjectManagement_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
