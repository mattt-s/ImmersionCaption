import Foundation

// Emits the production prompt for the public quality fixtures, without an app or microphone.
guard CommandLine.arguments.count == 2 else {
    fatalError("Expected one Chinese source phrase")
}
let input = TranslationInput(source: CommandLine.arguments[1])
print(TranslationPrompt.make(for: input))
