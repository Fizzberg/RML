'use server';

import { redirect } from 'next/navigation';

import { type Route } from 'next';
import { getLocale } from 'next-intl/server';
import { z } from 'zod';

import { createSupabaseServerClient } from '@/server/db/supabase-server';

import type { AuthFormState } from './types';

/**
 * Server actions for the auth skeleton.
 *
 * - Server-side validation only (`docs/SECURITY_RULES.md` §5). Client-side
 *   HTML attributes (`required`, `type="email"`, `minLength`) are UX.
 * - Errors are returned as STABLE KEYS — the form components translate
 *   them via next-intl. The action stays UI-agnostic and never leaks
 *   server-side detail.
 * - Locale-aware redirects: we resolve the current locale via
 *   `getLocale()` and prefix the path manually so a user signing in on
 *   `/en/login` returns to `/en/`, not the default-locale homepage.
 *
 * Note: the local Supabase stack has `[auth.email] enable_confirmations =
 * false` (see `supabase/config.toml`), so `signUp` creates a confirmed
 * user and starts a session immediately. If confirmations are ever
 * enabled, the sign-up flow needs a "check your email" surface instead
 * of a direct redirect.
 *
 * 'use server' files may only export async functions, so shared types and
 * constants live in `./types.ts`.
 */

const credentialsSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(320),
  password: z.string().min(6).max(128),
});

async function localePath(href: string): Promise<Route> {
  const locale = await getLocale();
  // next-intl localePrefix: 'as-needed' — default locale ('da') has no prefix.
  // Result is a dynamically-composed path; cast to Route for typedRoutes
  // since the prefix isn't part of the statically-known route set.
  const resolved = locale === 'da' ? href : `/${locale}${href === '/' ? '' : href}`;
  return resolved as Route;
}

export async function signInAction(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const parsed = credentialsSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
  });

  if (!parsed.success) {
    return { error: 'invalidInput' };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);

  if (error) {
    return { error: 'invalidCredentials' };
  }

  redirect(await localePath('/'));
}

export async function signUpAction(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const parsed = credentialsSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
  });

  if (!parsed.success) {
    return { error: 'invalidInput' };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signUp(parsed.data);

  if (error) {
    return { error: 'signUpFailed' };
  }

  // The handle_new_auth_user trigger has now created a profiles row.
  // With email confirmations disabled (local dev), a session is active.
  redirect(await localePath('/'));
}

/**
 * Sign-out action invoked from a plain `<form action={signOutAction}>`.
 * Plain-form actions receive a FormData argument from Next.js even when
 * unused — the parameter signature matches that contract.
 */
export async function signOutAction(_formData?: FormData): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect(await localePath('/'));
}
