class_name SimpleQR
extends RefCounted

# Minimal ISO/IEC 18004 QR Version 3-L (29x29, up to 53 UTF-8 bytes) generator for local URLs.
const VERSION := 3
const SIZE := 29
const DATA_CW := 55
const EC_CW := 15


static func make_texture(text: String, pixel_scale: int = 4, border: int = 2) -> ImageTexture:
	var grid := encode_v3_l(text)
	if grid.is_empty():
		return null
	var full := SIZE + border * 2
	var img_size := full * pixel_scale
	var img := Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for y in SIZE:
		for x in SIZE:
			if grid[y * SIZE + x] == 1:
				var px := (x + border) * pixel_scale
				var py := (y + border) * pixel_scale
				for dy in pixel_scale:
					for dx in pixel_scale:
						img.set_pixel(px + dx, py + dy, Color(0.03, 0.07, 0.14, 1.0))
	return ImageTexture.create_from_image(img)


static func encode_v3_l(text: String) -> PackedByteArray:
	var raw := text.to_utf8_buffer()
	if raw.size() > DATA_CW - 2:
		return PackedByteArray()

	# Byte mode header (0100) + 8-bit length + bytes + terminator + byte pad (0xEC, 0x11)
	var bits: Array[int] = []
	_append_bits(bits, 0b0100, 4)
	_append_bits(bits, raw.size(), 8)
	for b in raw:
		_append_bits(bits, b, 8)
	var max_bits := DATA_CW * 8
	for _i in mini(4, max_bits - bits.size()):
		bits.append(0)
	while bits.size() % 8 != 0:
		bits.append(0)

	var cw := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var v := 0
		for j in 8:
			v = (v << 1) | bits[i + j]
		cw.append(v)
	var pad_toggle := true
	while cw.size() < DATA_CW:
		cw.append(0xEC if pad_toggle else 0x11)
		pad_toggle = not pad_toggle

	var ec := _rs_remainder(cw, EC_CW)
	var all_cw := PackedByteArray()
	all_cw.append_array(cw)
	all_cw.append_array(ec)

	var mods := PackedByteArray()
	var func_mask := PackedByteArray()
	mods.resize(SIZE * SIZE)
	func_mask.resize(SIZE * SIZE)
	mods.fill(0)
	func_mask.fill(0)

	_draw_finder(mods, func_mask, 0, 0)
	_draw_finder(mods, func_mask, SIZE - 7, 0)
	_draw_finder(mods, func_mask, 0, SIZE - 7)
	_draw_alignment(mods, func_mask, 22, 22)
	for i in range(8, SIZE - 8):
		var v := 1 if (i % 2 == 0) else 0
		_set_func(mods, func_mask, 6, i, v)
		_set_func(mods, func_mask, i, 6, v)
	_set_func(mods, func_mask, 8, 4 * VERSION + 9, 1)
	_reserve_format(func_mask)

	# Zigzag data bitstream
	var bit_idx := 0
	var total_bits := all_cw.size() * 8
	var up := true
	var col := SIZE - 1
	while col > 0:
		if col == 6:
			col -= 1
		for step in SIZE:
			var y := (SIZE - 1 - step) if up else step
			for dx in 2:
				var x := col - dx
				if func_mask[y * SIZE + x] == 0:
					var bval := 0
					if bit_idx < total_bits:
						var byte_i := bit_idx >> 3
						var bit_i := 7 - (bit_idx & 7)
						bval = (all_cw[byte_i] >> bit_i) & 1
						bit_idx += 1
					mods[y * SIZE + x] = bval
		up = not up
		col -= 2

	# Evaluate masks and pick lowest penalty
	var best_mask := 0
	var best_pen := 1_000_000_000
	var best_grid := PackedByteArray()
	for mask_id in 8:
		var cand := mods.duplicate()
		for y in SIZE:
			for x in SIZE:
				if func_mask[y * SIZE + x] == 0 and _mask_bit(mask_id, y, x):
					cand[y * SIZE + x] ^= 1
		_write_format(cand, mask_id)
		var pen := _penalty_score(cand)
		if pen < best_pen:
			best_pen = pen
			best_mask = mask_id
			best_grid = cand
	return best_grid


static func _append_bits(out: Array[int], val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		out.append((val >> i) & 1)


static func _set_func(mods: PackedByteArray, mask: PackedByteArray, x: int, y: int, v: int) -> void:
	mods[y * SIZE + x] = v
	mask[y * SIZE + x] = 1


static func _draw_finder(mods: PackedByteArray, mask: PackedByteArray, x0: int, y0: int) -> void:
	for dy in range(-1, 8):
		for dx in range(-1, 8):
			var x := x0 + dx
			var y := y0 + dy
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE:
				continue
			var on := (dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6) and (
				dx == 0 or dx == 6 or dy == 0 or dy == 6 or (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4)
			)
			_set_func(mods, mask, x, y, 1 if on else 0)


static func _draw_alignment(mods: PackedByteArray, mask: PackedByteArray, cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var on := (absi(dx) == 2 or absi(dy) == 2 or (dx == 0 and dy == 0))
			_set_func(mods, mask, cx + dx, cy + dy, 1 if on else 0)


static func _reserve_format(mask: PackedByteArray) -> void:
	for i in 9:
		if i != 6:
			mask[8 * SIZE + i] = 1
			mask[i * SIZE + 8] = 1
	for i in range(SIZE - 8, SIZE):
		mask[8 * SIZE + i] = 1
	for i in range(SIZE - 7, SIZE):
		mask[i * SIZE + 8] = 1


static func _write_format(mods: PackedByteArray, mask_id: int) -> void:
	var data := (0b01 << 3) | (mask_id & 7) # EC level L = 01
	var rem := data << 10
	for i in range(14, 9, -1):
		if ((rem >> i) & 1) != 0:
			rem ^= (0x537 << (i - 10))
	var fmt := ((data << 10) | rem) ^ 0x5412

	for i in 15:
		var bit := (fmt >> i) & 1
		# Horizontal strip
		if i < 8:
			mods[8 * SIZE + (SIZE - 1 - i)] = bit
		else:
			var col := (14 - i) if i > 8 else 7
			mods[8 * SIZE + col] = bit
		# Vertical strip
		if i < 6:
			mods[i * SIZE + 8] = bit
		elif i == 6:
			mods[7 * SIZE + 8] = bit
		elif i == 7:
			mods[8 * SIZE + 8] = bit
		else:
			mods[(SIZE - 15 + i) * SIZE + 8] = bit


static func _mask_bit(mask_id: int, y: int, x: int) -> bool:
	match mask_id:
		0: return ((y + x) % 2) == 0
		1: return (y % 2) == 0
		2: return (x % 3) == 0
		3: return ((y + x) % 3) == 0
		4: return (((y >> 1) + int(x / 3.0)) % 2) == 0
		5: return ((y * x) % 2 + (y * x) % 3) == 0
		6: return ((((y * x) % 2) + ((y * x) % 3)) % 2) == 0
		_: return ((((y + x) % 2) + ((y * x) % 3)) % 2) == 0


static func _penalty_score(grid: PackedByteArray) -> int:
	var pen := 0
	for y in SIZE:
		var run_len := 1
		for x in range(1, SIZE):
			if grid[y * SIZE + x] == grid[y * SIZE + x - 1]:
				run_len += 1
				if run_len == 5:
					pen += 3
				elif run_len > 5:
					pen += 1
			else:
				run_len = 1
	for x in SIZE:
		var run_len := 1
		for y in range(1, SIZE):
			if grid[y * SIZE + x] == grid[(y - 1) * SIZE + x]:
				run_len += 1
				if run_len == 5:
					pen += 3
				elif run_len > 5:
					pen += 1
			else:
				run_len = 1
	return pen


static func _rs_remainder(data: PackedByteArray, ec_len: int) -> PackedByteArray:
	var gen := PackedByteArray([1])
	for i in ec_len:
		var root := _gf_pow2(i)
		var next := PackedByteArray()
		next.resize(gen.size() + 1)
		next.fill(0)
		for j in gen.size():
			next[j] ^= gen[j]
			next[j + 1] ^= _gf_mul(gen[j], root)
		gen = next

	var rem := PackedByteArray()
	rem.resize(ec_len)
	rem.fill(0)
	for b in data:
		var factor := b ^ rem[0]
		for j in ec_len - 1:
			rem[j] = rem[j + 1] ^ _gf_mul(gen[j + 1], factor)
		rem[ec_len - 1] = _gf_mul(gen[ec_len], factor)
	return rem


static func _gf_pow2(exp_val: int) -> int:
	var v := 1
	for _i in exp_val:
		v <<= 1
		if (v & 0x100) != 0:
			v ^= 0x11D
	return v


static func _gf_mul(a: int, b: int) -> int:
	var r := 0
	var x := a
	var y := b
	while y > 0:
		if (y & 1) != 0:
			r ^= x
		x <<= 1
		if (x & 0x100) != 0:
			x ^= 0x11D
		y >>= 1
	return r
