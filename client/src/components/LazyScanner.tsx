import { lazy, Suspense } from 'react';

const Scanner = lazy(() => import('./Scanner'));

/** The barcode library is most of the app's weight; only load it when a camera view opens. */
export default function LazyScanner(props: React.ComponentProps<typeof Scanner>) {
  return (
    <Suspense fallback={<div className="scanner-view" />}>
      <Scanner {...props} />
    </Suspense>
  );
}
