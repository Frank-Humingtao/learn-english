# Personal English Learning

A single-learner system for measuring and tracking English vocabulary, so the learner's level is precise enough for external agents to recommend suitable reading and video.

## Language

**Learner**:
The single person this system serves and models.
_Avoid_: User, student, account

**Observation**:
A single immutable record of the Learner's response to one word, from a Vocabulary Test or a Card review. Observations are only ever appended, never changed.
_Avoid_: Event, log entry, answer

**Learner Profile**:
The system's current picture of the Learner's vocabulary, always recomputed from Observations: every word's Word Band and probability of being known, the estimated vocabulary size, and what is needed to compute Coverage.
_Avoid_: Progress, level, stats

**Word Band**:
One of three classifications of a word relative to the Learner: Mastered, Target, or Distant.
_Avoid_: Difficulty, tier, grade

**Mastered**:
A Word Band for words too easy to need study; the Learner already knows them.
_Avoid_: Easy, known, 太简单

**Target**:
A Word Band for words within the Learner's reach and worth studying now.
_Avoid_: Learning, 正好该学

**Distant**:
A Word Band for words currently too far beyond the Learner to be useful; set aside for now.
_Avoid_: Hard, advanced, 太遥远

**Coverage**:
The share of the words in a given text that the Learner already knows. Comprehensible input means Coverage high enough to read without translation.
_Avoid_: Readability, difficulty score

**Vocabulary Test**:
A sampled assessment that estimates the Learner's total vocabulary and its Word Band distribution, and surfaces specific unknown words.
_Avoid_: Quiz, exam

**Baseline Test**:
The one-time full-length Vocabulary Test taken at the start, which later short tests refine.
_Avoid_: Placement test, initial test

**Card**:
A single word (lemma, not an individual sense) presented for spaced study, in the style of vocabulary apps and Anki decks.
_Avoid_: Flashcard, entry

**Progress Report**:
A concise snapshot of the Learner Profile published as a GitHub issue for external agents to read. A new one supersedes the previous one after each day's first Vocabulary Test; only the newest is current. It describes the Learner's level, never their content preferences.
_Avoid_: Status update, log, summary
