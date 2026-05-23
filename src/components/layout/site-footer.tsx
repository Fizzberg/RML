import { getTranslations } from 'next-intl/server';

export async function SiteFooter() {
  const t = await getTranslations();
  const year = new Date().getFullYear();

  return (
    <footer className="border-t bg-surface">
      <div className="container flex h-12 items-center justify-between text-xs text-muted-foreground">
        <span>© {year} {t('app.name')}</span>
        <span aria-label={t('footer.legal')}>—</span>
      </div>
    </footer>
  );
}
