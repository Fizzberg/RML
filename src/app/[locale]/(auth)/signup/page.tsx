import { getTranslations } from 'next-intl/server';

import { SignupForm } from '@/features/auth/signup-form';
import { Link } from '@/i18n/routing';

export const dynamic = 'force-dynamic';

export default async function SignupPage() {
  const t = await getTranslations();

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="text-lg font-medium tracking-tight">{t('auth.signup.title')}</h1>
        <p className="text-sm text-muted-foreground">{t('auth.signup.subtitle')}</p>
      </header>

      <SignupForm />

      <p className="text-xs text-muted-foreground">
        {t('auth.signup.linkToLogin')}{' '}
        <Link href="/login" className="underline hover:text-foreground">
          {t('nav.login')}
        </Link>
      </p>
    </div>
  );
}
