import Foundation
import ProfileEngineCLI

let code = ProfileEngineCLI.run(
    Array(CommandLine.arguments.dropFirst()),
    stdout: { FileHandle.standardOutput.write(Data($0.utf8)) },
    stderr: { FileHandle.standardError.write(Data($0.utf8)) })
exit(code)
