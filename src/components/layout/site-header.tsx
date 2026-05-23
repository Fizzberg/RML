import { getTranslations } from 'next-intl/server';

import { Link } from '@/i18n/routing';

export async function SiteHeader() {
  const t = await getTranslations();

  return (
    <header className="border-b bg-surface">
      <div className="container flex h-14 items-center justify-between">
        <Link href="/" className="text-sm font-semibold tracking-tight">
          {t('app.name')}
        </Link>
        <nav aria-label="Primary" className="flex items-center gap-4 text-sm text-muted-foreground">
          <Link href="/" className="hover:text-foreground">
            {t('nav.home')}
          </Link>
        </nav>
      </div>
    </header>
  );
}
