# Third-party notices

Sloppy depends on third-party software. Each dependency remains under its own
license; no entry in the Sloppy license map replaces those terms.

The current Swift dependency graph includes:

| Component | License family |
| --- | --- |
| AnyLanguageModel | Apache-2.0 |
| CodexBar, SweetCookieKit | MIT |
| EventSource, JSONSchema | MIT |
| PartialJSONDecoder | Apache-2.0 |
| swift-argument-parser | Apache-2.0 |
| swift-configuration | Apache-2.0 |
| swift-distributed-tracing | Apache-2.0 |
| swift-log | Apache-2.0 |
| swift-nio | Apache-2.0 |
| swift-system | Apache-2.0 |
| swift-tools-protocols | Apache-2.0 |
| modelcontextprotocol/swift-sdk | Apache-2.0 and legacy MIT; documentation may be CC-BY-4.0 |
| TeamSloppy/swift-acp | MIT |
| TauTUI | MIT |
| AdaEngine and AdaMCP | MIT |

Transitive Swift packages include Apple/Swift.org Apache-2.0 packages and
permissively licensed support packages. JavaScript packages used by Dashboard
and docs retain the license declared in their package metadata and installed
license files.

Official release archives contain a `share/sloppy/licenses/third-party`
directory generated from the exact resolved dependency checkout used for the
build. Those copied files are the authoritative third-party license and notice
texts for that binary.

When redistributing a custom build, regenerate and ship the license bundle:

```console
bash scripts/collect-third-party-licenses.sh path/to/licenses/third-party
```
