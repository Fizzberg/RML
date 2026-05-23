import { getTranslations } from 'next-intl/server';

export default async function ModerationPage() {
  const t = await getTranslations();

  return (
    <div>
      <h1 className="text-xl font-semibold tracking-tight">{t('moderation.title')}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{t('moderation.restricted')}</p>
      <p className="mt-4 text-sm text-muted-foreground">{t('common.scaffoldNotice')}</p>
    </div>
  );
}
