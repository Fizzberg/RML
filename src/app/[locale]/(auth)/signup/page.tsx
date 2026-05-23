import { getTranslations } from 'next-intl/server';

export default async function SignupPage() {
  const t = await getTranslations();

  return (
    <div>
      <h1 className="text-lg font-medium">{t('auth.signup.title')}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{t('common.scaffoldNotice')}</p>
    </div>
  );
}
