import { useI18n } from '../i18n';
import { useEffect, useState } from 'react';
import { Download, FileText } from 'lucide-react';
import type { Request, Row } from '../types';
import { Button, Markdown } from '../ui';
import { saveExport } from '../transport';

function Attachment({ block, run }: { block: Row; run: Request }) {
  const { t } = useI18n();
  const [asset, setAsset] = useState<Row | null>(null);
  useEffect(() => {
    let active = true;
    void run('attachment.load', { id: block.attachmentID }).then((result) => {
      if (active) setAsset(result);
    });
    return () => {
      active = false;
    };
  }, [block.attachmentID, run]);
  const type = asset?.mediaType || block.attachment?.media_type || '';
  if (asset?.base64 && /^image\/(png|jpe?g|gif|webp|avif)$/.test(type))
    return (
      <figure className="document-image">
        <img
          src={`data:${type};base64,${asset.base64}`}
          alt={block.attachment?.caption || t('Pièce jointe du document', 'Document attachment')}
          loading="lazy"
        />
        {block.attachment?.caption && <figcaption>{block.attachment.caption}</figcaption>}
      </figure>
    );
  return (
    <div className="attachment-file">
      <span>
        <FileText size={19} />
        {block.attachment?.filename || block.attachmentID}
      </span>
      {asset?.base64 ? (
        <Button
          icon={Download}
          onClick={() =>
            void saveExport(
              block.attachment?.filename ||
                `${block.attachmentID}${type === 'application/pdf' ? '.pdf' : '.bin'}`,
              asset.base64,
            )
          }
        >
          {' '}
          {t('Enregistrer la pièce jointe', 'Save attachment')}
        </Button>
      ) : (
        <span className="muted">
          {asset?.error || t('Chargement de la pièce jointe…', 'Loading attachment…')}
        </span>
      )}
    </div>
  );
}

export default function DocumentContent({
  reader,
  run,
  find = '',
}: {
  reader: Row;
  run: Request;
  find?: string;
}) {
  if (!reader.blocks?.length) return <Markdown text={reader.text} highlight={find} />;
  return (
    <div className="document-content">
      {reader.blocks.map((block: Row) =>
        block.type === 'text' ? (
          <Markdown key={block.id} text={block.text} highlight={find} />
        ) : (
          <Attachment key={block.id} block={block} run={run} />
        ),
      )}
    </div>
  );
}
