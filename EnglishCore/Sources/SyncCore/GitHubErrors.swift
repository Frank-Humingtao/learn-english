/// Classification of GitHub error payloads that drive sync decisions.
public enum GitHubErrors {
    /// Does this GraphQL error mean `createCommitOnBranch` lost the `expectedHeadOid`
    /// compare-and-swap (someone else moved the branch), so "re-read head and retry" is right?
    ///
    /// UNCONFIRMED: GitHub does not document this error. The predicate follows the format
    /// reported for the mutation (`type: "STALE_DATA"`, message
    /// `Expected branch to point to "<oid>" but it did not. Pull and try again.`).
    /// It MUST be checked against the real API once ticket 02 provides a repo and token
    /// (ticket 05, first acceptance box), and narrowed to whatever GitHub actually returns.
    public static func isStaleHead(type: String?, message: String) -> Bool {
        type == "STALE_DATA" || message.contains("Expected branch to point to")
    }
}
