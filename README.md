# SWIFT CBPR+ Investigations Ingestor

Windows C++ application that ingests SWIFT MX **CBPR+** investigation
messages (`camt.110.001.01` *InvestigationRequest* and `camt.111.001.02`
*InvestigationResponse*, SR2026 Usage Guidelines), parses them with
**CodeSynthesis XSD `cxx-tree`** bindings, and persists the result into the
`swift.*` MS SQL Server 2019 tables defined by
`swift_investigations_schema.sql`.

See `plans/swift_ingestor_plan.md` for the full design.

## Build

Requires Visual Studio 2026, CMake >= 3.28, CodeSynthesis XSD 4.2 and
Xerces-C 3.2 (both expected under `C:\tools\xsd` and `C:\tools\xerces`,
or via the `CODESYNTHESIS_XSD_ROOT` / `XERCES_ROOT` environment variables).

```bat
cmake --preset x64-debug
cmake --build --preset x64-debug --target xsd_generate
cmake --build --preset x64-debug
ctest --test-dir build/x64-debug --output-on-failure
```

## Regenerate XSD bindings only

```bat
cmake --build --preset x64-debug --target xsd_generate
```

Generated headers/sources land in `generated/<msg>/<UG>/Document.hxx,.cxx`
(git-ignored) and are compiled into the `swift_bindings` static library.

## Layout

See `plans/swift_ingestor_plan.md` §2 for the repository layout.
