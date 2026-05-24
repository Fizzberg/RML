import { getTranslations } from 'next-intl/server';

import { LogoutButton } from '@/features/auth/logout-button';
import { Link } from '@/i18n/routing';
import { getCurrentProfile } from '@/server/auth/get-current-profile';

export async function SiteHeader() {
  const t = await getTranslations();
  const profile = await getCurrentProfile();

  return (
    <header className="border-b bg-surface">
      <div className="container flex h-14 items-center justify-between">
        <Link href="/" className="text-sm font-semibold tracking-tight">
          {t('app.name')}
        </Link>
        <nav
          aria-label="Primary"
          className="flex items-center gap-4 text-sm text-muted-foreground"
        >
          <Link href="/" className="hover:text-foreground">
            {t('nav.home')}
          </Link>

          {profile ? (
            <>
              <span
                className="text-foreground"
                aria-label={t('nav.signedInAs', { name: profile.display_name })}
                title={t('nav.signedInAs', { name: profile.display_name })}
              >
                {profile.display_name}
              </span>
              <LogoutButton label={t('nav.logout')} />
            </>
          ) : (
            <>
              <Link href="/login" className="hover:text-foreground">
                {t('nav.login')}
              </Link>
              <Link href="/signup" className="hover:text-foreground">
                {t('nav.signup')}
              </Link>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}
