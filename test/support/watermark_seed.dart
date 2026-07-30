/// **KHA-157** — test setup for "this device has already been seeded".
///
/// ## Why almost every ingestion test now needs one line of setup
///
/// Until KHA-157, a watermark row straight out of a fresh database meant two
/// different things at once, and nothing could tell them apart:
///
///  1. *"nothing has ever been ingested here"* — a brand-new install; and
///  2. *"we are caught up as far as inbox row 0"*, i.e. read everything.
///
/// `runIncremental()` acted on the second reading, so on a real device the very
/// first sweep read the phone's **entire** SMS history and dropped 424
/// out-of-window messages into the review queue. The fix seeds the watermark to
/// the inbox's high-water mark before the first read, which makes reading (1)
/// the one the code takes.
///
/// **The fixtures could not express the bug**, which is exactly why it shipped:
/// every incremental test built an in-window inbox with a watermark at 0, so
/// "0 means the beginning of everything" was the fixture's invisible normal.
/// `docs/lessons.md` records the same fixture-blindness from KHA-137.
///
/// So a test that wants the *old* meaning has to say so now. That is not
/// ceremony — it is the fixture finally distinguishing two states that were
/// always different, and it makes each test's assumption visible in its own
/// `setUp` instead of hidden in a column default.
///
/// Use [seedWatermarkAtBeginning] when the test's subject is what the pipeline
/// **does with messages** (parsing, dedup, the ledger, categorization) and the
/// inbox is merely how they are delivered. Do **not** use it in a test about
/// the seed itself — see `kha157_watermark_seed_test.dart`, which deliberately
/// starts from the un-seeded state.
library;

import 'package:massrofy/data/dao/ingest_watermark_dao.dart';

/// Marks the watermark seeded, positioned **before every message** — the state
/// the fixtures used to get for free from the column default.
///
/// Writes provider id `0` with a non-null date, so KHA-157's
/// `lastProcessedSmsDate IS NULL` discriminator reads "already seeded" and
/// `runIncremental()` goes straight to reading `_id > 0`. The date is the epoch
/// rather than a plausible timestamp so that a test asserting on it fails
/// loudly rather than looking reasonable.
Future<void> seedWatermarkAtBeginning(IngestWatermarkDao dao) =>
    dao.seedTo(smsProviderId: 0, smsDate: DateTime.utc(1970));
