import { signOutAction } from './actions';

/**
 * Renders a single-button form that POSTs to the `signOutAction`
 * server action. Server component — no client JS shipped for this.
 */
export function LogoutButton({ label }: { label: string }) {
  return (
    <form action={signOutAction}>
      <button
        type="submit"
        className="text-muted-foreground hover:text-foreground focus-visible:text-foreground focus-visible:outline-none focus-visible:underline"
      >
        {label}
      </button>
    </form>
  );
}
