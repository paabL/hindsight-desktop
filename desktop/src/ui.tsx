import { memo, useEffect, useRef, type ReactNode } from 'react';
import {
  AlertCircle,
  ArrowUpRight,
  Check,
  CheckCircle2,
  ChevronRight,
  FileText,
  LoaderCircle,
  X,
  type LucideIcon,
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { nativeRequest } from './transport';
import { getLocale, translate as tr, useI18n } from './i18n';

// Formateurs créés une seule fois : en construire un par appel coûtait environ 30 µs, soit 150 ms
// pour une liste de 5 000 dates à chaque rendu.
const numberFormats = new Map<
  string,
  { standard: Intl.NumberFormat; compact: Intl.NumberFormat; money: Intl.NumberFormat }
>();
function formats() {
  const locale = getLocale();
  let value = numberFormats.get(locale);
  if (!value) {
    value = {
      standard: new Intl.NumberFormat(locale, { notation: 'standard', maximumFractionDigits: 0 }),
      compact: new Intl.NumberFormat(locale, { notation: 'compact', maximumFractionDigits: 1 }),
      money: new Intl.NumberFormat(locale, {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 2,
      }),
    };
    numberFormats.set(locale, value);
  }
  return value;
}
let dateFormats:
  | { offset: number; locale: string; day: Intl.DateTimeFormat; time: Intl.DateTimeFormat }
  | undefined;
function dateFormat(full: boolean) {
  // Recréés si le fuseau de la machine change en cours de session, comme un formateur créé à chaque appel.
  const offset = new Date().getTimezoneOffset();
  const locale = getLocale();
  if (dateFormats?.offset !== offset || dateFormats?.locale !== locale)
    dateFormats = {
      offset,
      locale,
      day: new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' }),
      time: new Intl.DateTimeFormat(locale, {
        day: 'numeric',
        month: 'short',
        hour: '2-digit',
        minute: '2-digit',
      }),
    };
  return full ? dateFormats.time : dateFormats.day;
}

export const number = (n: unknown, compact = false) =>
  typeof n === 'number' ? formats()[compact ? 'compact' : 'standard'].format(n) : '—';
export const money = (n: unknown) => (typeof n === 'number' ? formats().money.format(n) : '—');
export function date(value: unknown, full = false) {
  if (!value) return tr('Date inconnue', 'Unknown date');
  const d = new Date(String(value));
  return Number.isNaN(d.getTime())
    ? tr('Date inconnue', 'Unknown date')
    : dateFormat(full).format(d);
}
export const display = (value: unknown) =>
  typeof value === 'string' ? value : JSON.stringify(value, null, 2);
export const shortName = (value: string) => value?.split('/').filter(Boolean).at(-1) || value;

export function Logo({ small = false }: { small?: boolean }) {
  return (
    <span className={`brandmark ${small ? 'small' : ''}`} aria-hidden="true">
      <svg viewBox="0 0 48 48" fill="none">
        <path d="M7 24s6-11 17-11 17 11 17 11-6 11-17 11S7 24 7 24Z" />
        <circle cx="24" cy="24" r="5.5" />
        <path d="M24 5v3M24 40v3" />
      </svg>
    </span>
  );
}

export function Button({
  children,
  icon: Icon,
  kind = 'secondary',
  className = '',
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  icon?: LucideIcon;
  kind?: 'primary' | 'secondary' | 'ghost' | 'danger';
  children?: ReactNode;
}) {
  return (
    <button {...props} className={`button ${kind} ${className}`}>
      {Icon && <Icon size={16} strokeWidth={1.8} />} {children}
    </button>
  );
}
export function IconButton({
  icon: Icon,
  label,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { icon: LucideIcon; label: string }) {
  return (
    <button
      {...props}
      className={`icon-button ${props.className || ''}`}
      aria-label={label}
      title={label}
    >
      <Icon size={18} strokeWidth={1.7} />
    </button>
  );
}
export function Badge({ children, tone = 'neutral' }: { children: ReactNode; tone?: string }) {
  return <span className={`badge ${tone}`}>{children}</span>;
}
export function ErrorNotice({ message }: { message?: string | null }) {
  return message ? (
    <div className="notice error" role="alert">
      <AlertCircle size={17} />
      <span>{message}</span>
    </div>
  ) : null;
}
export function Empty({
  icon: Icon = FileText,
  title,
  description,
  action,
}: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="empty-state">
      <span className="empty-icon">
        <Icon size={28} strokeWidth={1.3} />
      </span>
      <h3>{title}</h3>
      {description && <p>{description}</p>}
      {action}
    </div>
  );
}
export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: string;
  title: string;
  description: string;
  actions?: ReactNode;
}) {
  return (
    <div className="page-header">
      <div>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      <div className="header-actions">{actions}</div>
    </div>
  );
}
export function CardHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: ReactNode;
}) {
  return (
    <div className="card-header">
      <div>
        <h2>{title}</h2>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}
export function Metric({
  label,
  value,
  note,
  icon: Icon,
  tone = 'accent',
}: {
  label: string;
  value: ReactNode;
  note?: string;
  icon: LucideIcon;
  tone?: string;
}) {
  return (
    <article className="metric">
      <div className="metric-top">
        <span>{label}</span>
        <span className={`metric-icon ${tone}`}>
          <Icon size={17} />
        </span>
      </div>
      <strong>{value}</strong>
      {note && <p>{note}</p>}
    </article>
  );
}
export function Tabs({
  value,
  onChange,
  items,
}: {
  value: string;
  onChange: (s: string) => void;
  items: { id: string; label: string; count?: number }[];
}) {
  return (
    <div className="tabs" role="tablist">
      {items.map((item) => (
        <button
          key={item.id}
          role="tab"
          aria-selected={value === item.id}
          className={value === item.id ? 'active' : ''}
          onClick={() => onChange(item.id)}
        >
          {item.label}
          {item.count != null && <span>{number(item.count)}</span>}
        </button>
      ))}
    </div>
  );
}
export function Modal({
  title,
  children,
  onClose,
  wide = false,
  subtitle,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  wide?: boolean;
  subtitle?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    const old = document.activeElement as HTMLElement;
    const container = ref.current;
    const focusable = () =>
      container?.querySelectorAll<HTMLElement>(
        'button:not(:disabled),input:not(:disabled),textarea,select,[tabindex="0"],a[href]',
      );
    (
      container?.querySelector<HTMLElement>('[autofocus],input,textarea') || focusable()?.[0]
    )?.focus();
    const listener = (event: KeyboardEvent) => {
      if (
        document.querySelectorAll('.modal').item(document.querySelectorAll('.modal').length - 1) !==
        container
      )
        return;
      if (event.key === 'Escape') {
        event.stopPropagation();
        closeRef.current();
      }
      if (event.key === 'Tab') {
        const list = focusable();
        if (!list?.length) return;
        const first = list[0],
          last = list[list.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener('keydown', listener);
    return () => {
      document.removeEventListener('keydown', listener);
      old?.focus();
    };
  }, []);
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        className={`modal ${wide ? 'wide' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="modal-header">
          <div>
            <h2>{title}</h2>
            {subtitle && <p>{subtitle}</p>}
          </div>
          <IconButton icon={X} label={tr('Fermer', 'Close')} onClick={onClose} />
        </div>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}
// Mémorisé : sans cela, chaque réponse du moteur faisait réanalyser tout le Markdown affiché.
export const Markdown = memo(function Markdown({
  text,
  highlight = '',
}: {
  text?: string | null;
  highlight?: string;
}) {
  const { t } = useI18n();
  const highlightPlugin = () => (tree: any) => {
    const query = highlight.trim().toLocaleLowerCase(getLocale());
    if (!query) return;
    const visit = (node: any) => {
      if (!node.children) return;
      node.children = node.children.flatMap((child: any) => {
        if (child.type !== 'text') {
          visit(child);
          return [child];
        }
        const value = child.value as string,
          lower = value.toLocaleLowerCase(getLocale());
        const parts = [];
        let start = 0,
          index = lower.indexOf(query);
        while (index >= 0) {
          if (index > start) parts.push({ type: 'text', value: value.slice(start, index) });
          parts.push({
            type: 'emphasis',
            data: { hName: 'mark' },
            children: [{ type: 'text', value: value.slice(index, index + query.length) }],
          });
          start = index + query.length;
          index = lower.indexOf(query, start);
        }
        if (start < value.length) parts.push({ type: 'text', value: value.slice(start) });
        return parts.length ? parts : [child];
      });
    };
    visit(tree);
  };
  return (
    <div className="markdown">
      <ReactMarkdown
        remarkPlugins={[remarkGfm, highlightPlugin]}
        components={{
          a: ({ href, children }) => (
            <button
              className="inline-link"
              title={href}
              onClick={() => {
                if (href && /^(https:\/\/|codex:|claude:)/.test(href))
                  void nativeRequest('external.open', { url: href }).catch(() => {});
              }}
            >
              {children}
              <ArrowUpRight size={12} />
            </button>
          ),
          img: ({ alt }) => (
            <span className="image-placeholder">
              {t('Image :', 'Image:')} {alt || t('pièce jointe', 'attachment')}
            </span>
          ),
        }}
      >
        {text || ''}
      </ReactMarkdown>
    </div>
  );
});
export function Loading() {
  return (
    <div className="loading-state" role="status">
      <LoaderCircle className="spin" size={22} />
      <span>{tr('Chargement de votre mémoire…', 'Loading your memory…')}</span>
    </div>
  );
}
export function Success({ children }: { children: ReactNode }) {
  return (
    <div className="notice success">
      <CheckCircle2 size={17} />
      {children}
    </div>
  );
}
export function Step({
  number: n,
  title,
  text,
  active = false,
}: {
  number: number;
  title: string;
  text: string;
  active?: boolean;
}) {
  return (
    <div className={`pipeline-step ${active ? 'active' : ''}`}>
      <span>{active ? <Check size={14} /> : n}</span>
      <div>
        <strong>{title}</strong>
        <p>{text}</p>
      </div>
      <ChevronRight size={14} />
    </div>
  );
}
