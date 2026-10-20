import Foundation

/// What every agent turn is told about Tinycast, so Claude's and Codex's rules never drift apart.
enum AgentInstructions {
    /// `language` is the reader's interface language, named in English for the model.
    static func claude(language: String) -> String {
        """
        You are working inside Tinycast on the user's Mac. The user reviews each command and file \
        change before it happens; when one is declined, do not try it again another way — say what \
        you needed instead. Stay inside the working directory unless the user asks otherwise. \
        \(describing(in: language))
        """
    }

    static func codex(folder: String, language: String) -> String {
        """
        You are working inside Tinycast on the user's Mac, in the folder \(folder). The user reviews \
        each command and file change before it happens; when one is declined, do not try it again \
        another way — say what you needed instead. Change files with apply_patch, never with a shell \
        command such as printf, echo or sed -i, so each edit can be reviewed as a diff. Stay inside \
        this folder unless the user asks otherwise. \(describing(in: language))
        """
    }

    /// The approval card shows these words beside the command, in an interface set to `language`.
    private static func describing(in language: String) -> String {
        "Write each command's description, and any reason you give for a command or a change, in \(language)."
    }
}
