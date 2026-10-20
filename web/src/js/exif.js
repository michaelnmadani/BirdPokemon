// Tiny JPEG EXIF reader: just the capture time and GPS position, which is all
// the app needs. Returns { takenAt: Date|null, coordinate: {lat, lon}|null }.

const TAG_EXIF_IFD = 0x8769;
const TAG_GPS_IFD = 0x8825;
const TAG_DATETIME_ORIGINAL = 0x9003;
const TAG_OFFSET_TIME_ORIGINAL = 0x9011;
const GPS_LAT_REF = 0x0001, GPS_LAT = 0x0002, GPS_LON_REF = 0x0003, GPS_LON = 0x0004;

export function readExif(buffer) {
  const none = { takenAt: null, coordinate: null };
  try {
    const view = new DataView(buffer);
    if (view.getUint16(0) !== 0xffd8) return none; // not a JPEG
    let offset = 2;
    while (offset + 4 < view.byteLength) {
      const marker = view.getUint16(offset);
      const length = view.getUint16(offset + 2);
      if (marker === 0xffe1 && view.getUint32(offset + 4) === 0x45786966) { // "Exif"
        return parseTiff(view, offset + 10);
      }
      if ((marker & 0xff00) !== 0xff00 || marker === 0xffda) break; // start of scan
      offset += 2 + length;
    }
  } catch {
    // Malformed metadata is common; treat it as absent.
  }
  return none;
}

function parseTiff(view, tiff) {
  const little = view.getUint16(tiff) === 0x4949;
  const u16 = (o) => view.getUint16(o, little);
  const u32 = (o) => view.getUint32(o, little);

  const readIfd = (ifdOffset) => {
    const entries = new Map();
    const start = tiff + ifdOffset;
    const count = u16(start);
    for (let i = 0; i < count; i++) {
      const e = start + 2 + i * 12;
      entries.set(u16(e), { type: u16(e + 2), count: u32(e + 4), valueOffset: e + 8 });
    }
    return entries;
  };

  const ascii = (entry) => {
    if (!entry) return null;
    const at = entry.count > 4 ? tiff + u32(entry.valueOffset) : entry.valueOffset;
    let s = '';
    for (let i = 0; i < entry.count - 1; i++) s += String.fromCharCode(view.getUint8(at + i));
    return s;
  };

  const rationals = (entry) => {
    if (!entry) return null;
    const at = tiff + u32(entry.valueOffset);
    const out = [];
    for (let i = 0; i < entry.count; i++) out.push(u32(at + i * 8) / u32(at + i * 8 + 4));
    return out;
  };

  const ifd0 = readIfd(u32(tiff + 4));
  let takenAt = null;
  const exifPtr = ifd0.get(TAG_EXIF_IFD);
  if (exifPtr) {
    const exif = readIfd(u32(exifPtr.valueOffset));
    takenAt = parseExifDate(ascii(exif.get(TAG_DATETIME_ORIGINAL)), ascii(exif.get(TAG_OFFSET_TIME_ORIGINAL)));
  }

  let coordinate = null;
  const gpsPtr = ifd0.get(TAG_GPS_IFD);
  if (gpsPtr) {
    const gps = readIfd(u32(gpsPtr.valueOffset));
    const lat = toDegrees(rationals(gps.get(GPS_LAT)));
    const lon = toDegrees(rationals(gps.get(GPS_LON)));
    if (lat !== null && lon !== null) {
      const latRef = ascii(gps.get(GPS_LAT_REF));
      const lonRef = ascii(gps.get(GPS_LON_REF));
      coordinate = {
        lat: latRef?.toUpperCase().startsWith('S') ? -lat : lat,
        lon: lonRef?.toUpperCase().startsWith('W') ? -lon : lon,
      };
      if (Math.abs(coordinate.lat) > 90 || Math.abs(coordinate.lon) > 180) coordinate = null;
    }
  }
  return { takenAt, coordinate };
}

function toDegrees(parts) {
  if (!parts || parts.length < 3 || parts.some((p) => !Number.isFinite(p))) return null;
  return parts[0] + parts[1] / 60 + parts[2] / 3600;
}

/** "2025:09:14 07:30:00" (+ optional "+10:00") -> Date in local time or with offset. */
export function parseExifDate(stamp, offset) {
  const m = stamp?.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/);
  if (!m) return null;
  const [, y, mo, d, h, mi, s] = m;
  if (offset && /^[+-]\d{2}:\d{2}$/.test(offset)) {
    const date = new Date(`${y}-${mo}-${d}T${h}:${mi}:${s}${offset}`);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
}
