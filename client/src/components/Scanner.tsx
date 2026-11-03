import { useEffect, useRef, useState } from 'react';
import { BrowserMultiFormatReader, type IScannerControls } from '@zxing/browser';
import { BarcodeFormat, DecodeHintType, type Result } from '@zxing/library';

const hints = new Map<DecodeHintType, unknown>([
  [DecodeHintType.POSSIBLE_FORMATS, [BarcodeFormat.UPC_A, BarcodeFormat.UPC_E, BarcodeFormat.EAN_13, BarcodeFormat.EAN_8, BarcodeFormat.CODE_128]],
  [DecodeHintType.TRY_HARDER, true],
]);

/** UPC-E is the short code on small packages; stores and Tackle Warehouse list the full UPC-A. */
export function expandUpcE(code: string) {
  if (!/^[01]\d{7}$/.test(code)) return code;
  const [n, d1, d2, d3, d4, d5, d6, c] = code;
  if ('012'.includes(d6)) return n + d1 + d2 + d6 + '0000' + d3 + d4 + d5 + c;
  if (d6 === '3') return n + d1 + d2 + d3 + '00000' + d4 + d5 + c;
  if (d6 === '4') return n + d1 + d2 + d3 + d4 + '00000' + d5 + c;
  return n + d1 + d2 + d3 + d4 + d5 + '0000' + d6 + c;
}

function codeFrom(result: Result) {
  const text = result.getText();
  return result.getBarcodeFormat() === BarcodeFormat.UPC_E ? expandUpcE(text) : text;
}

const liveCameraAvailable = () => window.isSecureContext && !!navigator.mediaDevices?.getUserMedia;

export default function Scanner({ onDetected, paused = false }: {
  onDetected: (code: string, source: 'camera' | 'manual') => void;
  paused?: boolean;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const onDetectedRef = useRef(onDetected);
  onDetectedRef.current = onDetected;
  const [error, setError] = useState<string | null>(liveCameraAvailable() ? null : 'insecure');
  const [torch, setTorch] = useState(false);
  const [torchSupported, setTorchSupported] = useState(false);
  const [manual, setManual] = useState('');
  const [decoding, setDecoding] = useState(false);

  useEffect(() => {
    if (paused || !liveCameraAvailable() || !videoRef.current) return;
    let cancelled = false;
    const reader = new BrowserMultiFormatReader(hints, { delayBetweenScanAttempts: 150 });
    reader
      .decodeFromConstraints(
        { video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } } },
        videoRef.current,
        (result) => {
          if (result && !cancelled) {
            navigator.vibrate?.(60);
            onDetectedRef.current(codeFrom(result), 'camera');
          }
        },
      )
      .then((controls) => {
        if (cancelled) return controls.stop();
        controlsRef.current = controls;
        setTorchSupported(!!controls.switchTorch);
        setError(null);
      })
      .catch((e: Error) => !cancelled && setError(e.name === 'NotAllowedError' ? 'denied' : e.message));
    return () => {
      cancelled = true;
      controlsRef.current?.stop();
      controlsRef.current = null;
      setTorch(false);
    };
  }, [paused]);

  async function toggleTorch() {
    const next = !torch;
    await controlsRef.current?.switchTorch?.(next);
    setTorch(next);
  }

  async function decodePhoto(file: File | undefined) {
    if (!file) return;
    setDecoding(true);
    const url = URL.createObjectURL(file);
    try {
      const result = await new BrowserMultiFormatReader(hints).decodeFromImageUrl(url);
      onDetected(codeFrom(result), 'manual');
    } catch {
      alert('No barcode found in that photo. Try again closer, with the barcode flat and in focus.');
    } finally {
      URL.revokeObjectURL(url);
      setDecoding(false);
    }
  }

  function submitManual(e: React.FormEvent) {
    e.preventDefault();
    const digits = manual.replace(/\D/g, '');
    if (digits.length >= 6) {
      onDetected(digits.length === 8 ? expandUpcE(digits) : digits, 'manual');
      setManual('');
    }
  }

  return (
    <div className="scanner">
      {error ? (
        <div className="scanner-message">
          {error === 'insecure' && <p>Live scanning needs the secure (https) address. You can still snap a photo of the barcode.</p>}
          {error === 'denied' && <p>Camera access was blocked. Allow the camera for this site in your browser settings, or snap a photo instead.</p>}
          {error !== 'insecure' && error !== 'denied' && <p>Couldn't start the camera: {error}</p>}
        </div>
      ) : (
        <div className="scanner-view">
          <video ref={videoRef} muted playsInline />
          <div className="scanner-reticle" aria-hidden />
          {torchSupported && (
            <button type="button" className="torch" onClick={toggleTorch} aria-pressed={torch}>
              {torch ? 'Light off' : 'Light on'}
            </button>
          )}
        </div>
      )}
      <div className="scanner-alt">
        <label className="btn secondary">
          {decoding ? 'Reading…' : 'Snap photo of barcode'}
          <input type="file" accept="image/*" capture="environment" hidden onChange={(e) => decodePhoto(e.target.files?.[0])} />
        </label>
        <form onSubmit={submitManual} className="manual">
          <input inputMode="numeric" placeholder="Or type UPC" value={manual} onChange={(e) => setManual(e.target.value)} aria-label="UPC" />
          <button className="btn" disabled={manual.replace(/\D/g, '').length < 6}>Go</button>
        </form>
      </div>
    </div>
  );
}
