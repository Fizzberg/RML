import { getTranslations } from 'next-intl/server';

import { LoginForm } from '@/features/auth/login-form';
import { Link } from '@/i18n/routing';

export const dynamic = 'force-dynamic';

export default async function LoginPage() {
  const t = await getTranslations();

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="text-lg font-medium tracking-tight">{t('auth.login.title')}</h1>
        <p className="text-sm text-muted-foreground">{t('auth.login.subtitle')}</p>
      </header>

      <LoginForm />

      <p className="text-xs text-muted-foreground">
        {t('auth.login.linkToSignup')}{' '}
        <Link href="/signup" className="underline hover:text-foreground">
          {t('nav.signup')}
        </Link>
      </p>
    </div>
  );
}
