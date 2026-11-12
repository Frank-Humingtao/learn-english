"""Tests for build_lexicon.py on tiny synthetic inputs (no network).

Run: python3 -I tools/lexicon-build/test_build_lexicon.py
"""
import csv
import json
import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_lexicon  # noqa: E402


def write_inputs(cache):
    # BNC/COCA families: level 1 has HAPPY (+ inflections, a derivation) and RUN; level 2 has QUAY.
    with zipfile.ZipFile(os.path.join(cache, build_lexicon.BASEWORDS_ZIP), "w") as z:
        z.writestr("basewrd1.txt",
                   "HAPPY 500\r\n\tHAPPIER 50\r\n\tHAPPIEST 20\r\n\tHAPPINESS 200\r\n\tUNHAPPY 100\r\n"
                   "RUN 900\r\n\tRAN 300\r\n\tRUNS 200\r\n\tRUNNER 80\r\n"
                   "BE 9000\r\n\tIS 5000\r\n\tISN 40\r\n\tS 900\r\n")
        z.writestr("basewrd2.txt", "QUAY 30\r\n\tQUAYS 5\r\n")
        z.writestr("basewrd31.txt", "LONDON 999\r\n\tLONDONER 10\r\n")
        z.writestr("basewrd34.txt", "BBC 100\r\n")
    with open(os.path.join(cache, build_lexicon.LEMMA_FILE), "w", encoding="utf-8") as f:
        f.write("; header\nbe/14000 -> is\nhappy/600 -> happier,happiest\nrun/1400 -> ran,runs,running\nquay/35 -> quays\n")
    with open(os.path.join(cache, build_lexicon.ECDICT_FILE), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["word", "phonetic", "definition", "translation", "pos", "collins", "oxford", "tag",
                    "bnc", "frq", "exchange", "detail", "audio"])
        w.writerow(["happy", "'hæpi", "a. enjoying well-being", "a. 快乐的\\n幸福的", "j:100", "5", "1",
                    "zk gk cet4", "500", "600", "r:happier/t:happiest", "", ""])
        w.writerow(["happiness", "'hæpinis", "n. state of well-being", "n. 幸福", "n:100", "", "", "cet4",
                    "", "", "", "", ""])
        w.writerow(["run", "rʌn", "v. move fast", "v. 跑", "v:80/n:20", "", "", "zk", "", "",
                    "p:ran/d:run/i:running/3:runs", "", ""])
        w.writerow(["runner", "'rʌnə", "n. one who runs", "n. 跑步者", "", "", "", "", "", "", "", "", ""])
        w.writerow(["quay", "ki:", "n. a landing place", "n. 码头", "", "", "", "", "", "", "s:quays", "", ""])
        w.writerow(["isn", "", "", "abbr. 某缩写", "", "", "", "", "", "", "", "", ""])
        w.writerow(["s", "", "", "abbr. 秒", "", "", "", "", "", "", "", "", ""])
        w.writerow(["unhappy", "ʌn'hæpi", "a. sad", "a. 不快乐的", "", "", "", "", "", "", "", "", ""])
    with open(os.path.join(cache, build_lexicon.KAIKKI_FILE), "w", encoding="utf-8") as f:
        def entry(word, examples, sounds, lang="English", code="en"):
            return json.dumps({"pos": "adj", "word": word, "lang": lang, "lang_code": code, "sounds": sounds,
                               "senses": [{"examples": examples}]}) + "\n"
        f.write(entry("happy", [{"text": "A long quotation " * 30, "type": "quotation"},
                                {"text": "She looks happy.", "type": "example"}],
                      [{"ipa": "/ˈhæpi/"}, {"audio": "a.ogg", "mp3_url": "https://upload.example/happy.mp3"}]))
        f.write(entry("happy", [{"text": "Second entry example.", "type": "example"}], []))
        f.write(entry("quay", [], [{"ipa": "/kiː/"}]))
        f.write(entry("runner", [{"text": "Il court.", "type": "example"}], [], lang="French", code="fr"))


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        rows = [line.rstrip("\n").split("\t") for line in f]
    header, body = rows[0], rows[1:]
    return [dict(zip(header, r)) for r in body]


class BuildLexiconTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = os.path.join(self.tmp.name, "cache")
        self.out = os.path.join(self.tmp.name, "out")
        os.makedirs(self.cache)
        write_inputs(self.cache)
        build_lexicon.build(cache=self.cache, out=self.out, download=False)
        self.words = {r["lemma"]: r for r in read_tsv(os.path.join(self.out, "words.tsv"))}
        self.forms = {r["form"]: r["lemma"] for r in read_tsv(os.path.join(self.out, "forms.tsv"))}

    def tearDown(self):
        self.tmp.cleanup()

    def test_lemmas_exclude_inflections_but_keep_derivations(self):
        self.assertEqual(set(self.words), {"be", "happy", "happiness", "unhappy", "run", "runner", "quay"})

    def test_contraction_fragments_are_not_lemmas(self):
        self.assertNotIn("isn", self.words)
        self.assertNotIn("s", self.words)

    def test_ranks_follow_level_then_frequency(self):
        ranks = sorted(self.words.values(), key=lambda r: int(r["rank"]))
        self.assertEqual([r["lemma"] for r in ranks], ["be", "run", "happy", "happiness", "unhappy", "runner", "quay"])
        self.assertEqual(self.words["happiness"]["family"], "happy")
        self.assertEqual(self.words["quay"]["level"], "2")
        # run's family (freq 1480) outranks happy's (870).
        self.assertEqual(self.words["run"]["family_rank"], "2")
        self.assertEqual(self.words["happy"]["family_rank"], "3")

    def test_dictionary_fields_come_from_ecdict_and_wiktextract(self):
        happy = self.words["happy"]
        self.assertEqual(happy["phonetic"], "'hæpi")
        self.assertEqual(happy["translation"], "a. 快乐的\\n幸福的")
        self.assertEqual(happy["tags"], "zk gk cet4")
        self.assertEqual(happy["example"], "She looks happy.")
        self.assertEqual(happy["audio"], "https://upload.example/happy.mp3")
        # Non-English Wiktextract entries are ignored.
        self.assertEqual(self.words["runner"]["example"], "")

    def test_forms_map_inflections_to_lemmas(self):
        self.assertEqual(self.forms["ran"], "run")
        self.assertEqual(self.forms["running"], "run")
        self.assertEqual(self.forms["happier"], "happy")
        self.assertEqual(self.forms["quays"], "quay")
        self.assertNotIn("happy", self.forms)

    def test_supplementary_lists_and_version(self):
        with open(os.path.join(self.out, "supplementary.txt"), encoding="utf-8") as f:
            supp = f.read().split()
        self.assertEqual(supp, ["bbc", "london", "londoner"])
        with open(os.path.join(self.out, "meta.json"), encoding="utf-8") as f:
            meta = json.load(f)
        self.assertTrue(meta["version"].startswith("lex-"))
        self.assertEqual(meta["counts"]["lemmas"], 7)

    def test_build_is_reproducible(self):
        out2 = os.path.join(self.tmp.name, "out2")
        build_lexicon.build(cache=self.cache, out=out2, download=False)
        for name in ["meta.json", "words.tsv", "forms.tsv", "supplementary.txt"]:
            with open(os.path.join(self.out, name), "rb") as a, open(os.path.join(out2, name), "rb") as b:
                self.assertEqual(a.read(), b.read(), name)

    def meta(self, out):
        with open(os.path.join(out, "meta.json"), encoding="utf-8") as f:
            return json.load(f)

    def test_wiktextract_content_does_not_change_the_version(self):
        # GitHub Actions builds without Wiktextract (empty file); the App bundle has it.
        bare = os.path.join(self.tmp.name, "bare")
        with open(os.path.join(self.cache, build_lexicon.KAIKKI_FILE), "w") as f:
            f.write("")
        build_lexicon.build(cache=self.cache, out=bare, download=False)
        self.assertEqual(read_tsv(os.path.join(bare, "words.tsv"))[2]["example"], "")
        self.assertEqual(self.meta(bare)["version"], self.meta(self.out)["version"])
        with open(os.path.join(bare, "forms.tsv"), "rb") as a, open(os.path.join(self.out, "forms.tsv"), "rb") as b:
            self.assertEqual(a.read(), b.read())

    def test_profile_relevant_changes_do_change_the_version(self):
        zip_path = os.path.join(self.cache, build_lexicon.BASEWORDS_ZIP)
        with zipfile.ZipFile(zip_path, "a") as z:
            z.writestr("basewrd3.txt", "ZEBRA 3\r\n")
        other = os.path.join(self.tmp.name, "other")
        build_lexicon.build(cache=self.cache, out=other, download=False)
        self.assertNotEqual(self.meta(other)["version"], self.meta(self.out)["version"])

    def test_version_can_be_recomputed_from_a_built_directory(self):
        self.assertEqual(build_lexicon.version_of(self.out), self.meta(self.out)["version"])

    def test_committed_fixture_carries_its_content_version(self):
        fixture = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "EnglishCore", "Fixtures",
                               "lexicon")
        self.assertEqual(build_lexicon.version_of(fixture), self.meta(fixture)["version"])

    def test_profile_relevant_sources_are_pinned(self):
        for name in (build_lexicon.BASEWORDS_ZIP, build_lexicon.ECDICT_FILE, build_lexicon.LEMMA_FILE):
            self.assertRegex(build_lexicon.SHA256[name], r"^[0-9a-f]{64}$")
        for name in (build_lexicon.ECDICT_FILE, build_lexicon.LEMMA_FILE):
            self.assertIn(build_lexicon.ECDICT_COMMIT, build_lexicon.SOURCES[name])
        with self.assertRaises(SystemExit):  # a cached file that is not the pinned one is refused
            build_lexicon.verify_source(self.cache, build_lexicon.ECDICT_FILE)

    def test_sampling_keeps_true_ranks(self):
        out3 = os.path.join(self.tmp.name, "out3")
        build_lexicon.build(cache=self.cache, out=out3, download=False, sample_every=2)
        rows = read_tsv(os.path.join(out3, "words.tsv"))
        # Families 1 (be), 3 (happy) are kept, with their original ranks; 2 (run) and 4 (quay) dropped.
        self.assertEqual({r["lemma"]: r["rank"] for r in rows},
                         {"be": "1", "happy": "3", "happiness": "4", "unhappy": "5"})
        with open(os.path.join(out3, "supplementary.txt"), encoding="utf-8") as f:
            self.assertEqual(f.read().split(), ["bbc", "londoner"])


if __name__ == "__main__":
    unittest.main()
