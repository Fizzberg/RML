/**
 * Shared types and constants for the auth feature.
 *
 * This file is intentionally NOT marked `'use server'` so it can export
 * non-function values (the initial form state) alongside types. The server
 * actions in `./actions.ts` import from here.
 */

export type AuthErrorKey =
  | 'invalidInput'
  | 'invalidCredentials'
  | 'signUpFailed';

export interface AuthFormState {
  error: AuthErrorKey | null;
}

export const INITIAL_AUTH_STATE: AuthFormState = { error: null };
