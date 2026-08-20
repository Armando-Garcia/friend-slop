extends RefCounted

const GdvoskAdapterScript := preload("res://scripts/spells/gdvosk_adapter.gd")


func run() -> int:
	var failures := 0
	failures += _test_extract_words_from_alternatives()
	failures += _test_extract_words_from_result_entries()
	failures += _test_extract_words_from_text_field()
	failures += _test_extract_words_skips_unk()
	failures += _test_downsample_rejects_aliasing()
	failures += _test_downsample_keeps_speech_band()
	return failures


## Point-sampling 88.2 kHz down to 16 kHz folds a 20 kHz tone into the speech
## band as a loud phantom, which is what made Vosk fail on audible casts.
func _test_downsample_rejects_aliasing() -> int:
	var out := _resampled_tone(20000.0)
	var peak := _peak(out)
	if peak > 0.1:
		push_error(
			"Expected 20 kHz tone to be filtered before decimation, peak=%.3f" % peak
		)
		return 1
	return 0


func _test_downsample_keeps_speech_band() -> int:
	var out := _resampled_tone(1000.0)
	var peak := _peak(out)
	if peak < 0.7:
		push_error("Expected 1 kHz tone to survive resampling, peak=%.3f" % peak)
		return 1
	return 0


func _resampled_tone(tone_hz: float) -> PackedFloat32Array:
	var source_rate := 88200
	var count := source_rate / 4
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = sin(TAU * tone_hz * float(i) / float(source_rate))
	return GdvoskAdapterScript._resample_for_vosk(samples, source_rate, 16000)


func _peak(samples: PackedFloat32Array) -> float:
	## Skip the filter's startup transient.
	var peak := 0.0
	for i in range(mini(64, samples.size()), samples.size()):
		peak = maxf(peak, absf(samples[i]))
	return peak


func _test_extract_words_from_alternatives() -> int:
	var parsed: Dictionary = GdvoskAdapterScript.extract_words_and_starts({
		"alternatives": [{"confidence": 1.0, "text": "fire ball"}],
	})
	var words: PackedStringArray = parsed.get("words", PackedStringArray())
	if words.size() != 2 or words[0] != "fire" or words[1] != "ball":
		push_error("Expected alternatives text to split into tokens, got: %s" % words)
		return 1
	return 0


func _test_extract_words_from_result_entries() -> int:
	var parsed: Dictionary = GdvoskAdapterScript.extract_words_and_starts({
		"result": [{"word": "fireball", "start": 0.4}],
	})
	var words: PackedStringArray = parsed.get("words", PackedStringArray())
	if words.size() != 1 or words[0] != "fireball":
		push_error("Expected result entry words, got: %s" % words)
		return 1
	return 0


func _test_extract_words_from_text_field() -> int:
	var parsed: Dictionary = GdvoskAdapterScript.extract_words_and_starts({
		"text": "show me",
	})
	var words: PackedStringArray = parsed.get("words", PackedStringArray())
	if words.size() != 2 or words[0] != "show" or words[1] != "me":
		push_error("Expected text field words show/me, got: %s" % words)
		return 1
	return 0


func _test_extract_words_skips_unk() -> int:
	var parsed: Dictionary = GdvoskAdapterScript.extract_words_and_starts({
		"alternatives": [{"confidence": 1.0, "text": "[unk] fireball [unk]"}],
	})
	var words: PackedStringArray = parsed.get("words", PackedStringArray())
	if words.size() != 1 or words[0] != "fireball":
		push_error("Expected [unk] tokens stripped, got: %s" % words)
		return 1
	return 0
