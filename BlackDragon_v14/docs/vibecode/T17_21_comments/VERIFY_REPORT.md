# T17.21 verification scope

The change writes readable pipe-delimited RH comments and PYR comments while
keeping Core DCA unchanged. Legacy BDR/BDP readers remain available for migration.
Validation compiles the actual codec and runtime presentation helper, checks
literal old/new identities and protective round reconstruction, and proves each
existing-source change against a reversible baseline manifest. All unrelated
runtime headers are pinned by hash. Existing lot/SL/NewCycle findings are outside
this task and remain unchanged.

The canonical workflow enrolls all models, source contracts and native suites,
requires zero MetaEditor errors/warnings and binds its artifact to the branch
head/tree. Detailed execution evidence is delivered separately to the owner.
Broker restart and full owner Strategy Tester acceptance remain in OWNER_QA_CHECKLIST.md.
