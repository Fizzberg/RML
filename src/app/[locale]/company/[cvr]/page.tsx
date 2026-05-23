import { getTranslations } from 'next-intl/server';

interface CompanyPageProps {
  params: Promise<{ cvr: string }>;
}

export default async function CompanyPage({ params }: CompanyPageProps) {
  const { cvr } = await params;
  const t = await getTranslations();

  return (
    <section className="container py-8">
      <h1 className="text-xl font-semibold tracking-tight">{t('company.title')}</h1>
      <p className="mt-1 font-mono text-xs text-muted-foreground">cvr: {cvr}</p>
      <p className="mt-4 text-sm text-muted-foreground">{t('common.scaffoldNotice')}</p>
    </section>
  );
}
