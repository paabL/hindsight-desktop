import { translate as t } from './i18n-core.ts';

// États d'un fichier ou d'une source par rapport à la banque : mêmes mots dans un dossier ordinaire et dans
// un catalogue. « En file » attend l'extraction (« En attente » dans Traitements), jamais « En cours ».
export const sharedFileStates = {
  get toUpload() {
    return t('À envoyer', 'To upload');
  },
  get current() {
    return t('À jour', 'Up to date');
  },
  get modified() {
    return t('Modifié depuis l’envoi', 'Changed since upload');
  },
  get queued() {
    return t('En file', 'Queued');
  },
  get excluded() {
    return t('Exclu des envois', 'Excluded from uploads');
  },
};
