'use client';

import { useActionState } from 'react';

import { useTranslations } from 'next-intl';

import { signInAction } from './actions';
import { INITIAL_AUTH_STATE } from './types';

export function LoginForm() {
  const t = useTranslations('auth');
  const [state, formAction, isPending] = useActionState(signInAction, INITIAL_AUTH_STATE);

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-1">
        <label htmlFor="login-email" className="block text-xs font-medium text-foreground">
          {t('fields.email')}
          <span aria-hidden="true" className="ml-0.5 text-destructive">*</span>
        </label>
        <input
          id="login-email"
          name="email"
          type="email"
          autoComplete="email"
          required
          aria-required="true"
          className="w-full rounded-md border border-input bg-surface px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        />
      </div>

      <div className="space-y-1">
        <label htmlFor="login-password" className="block text-xs font-medium text-foreground">
          {t('fields.password')}
          <span aria-hidden="true" className="ml-0.5 text-destructive">*</span>
        </label>
        <input
          id="login-password"
          name="password"
          type="password"
          autoComplete="current-password"
          minLength={6}
          required
          aria-required="true"
          className="w-full rounded-md border border-input bg-surface px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        />
      </div>

      {state.error !== null && (
        <p role="alert" className="text-xs text-destructive">
          {t(`errors.${state.error}`)}
        </p>
      )}

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex h-9 items-center justify-center rounded-md bg-primary px-4 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:opacity-50"
      >
        {t('login.submit')}
      </button>
    </form>
  );
}
