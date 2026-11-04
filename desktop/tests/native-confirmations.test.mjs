import test from 'node:test';
import assert from 'node:assert/strict';
import { setLanguage } from '../src/i18n-core.ts';
import { advancedConfirmationMessage } from '../src/native-confirmations.ts';

test('la fusion garde les identifiants et explique remplacement, suppression et coût différé', () => {
  setLanguage('en');
  const body =
    "Les documents de « source-1 » (1 234 faits) sont ajoutés à « target.2 » (87 faits).\nSans appel LLM : les faits sont ré-indexés avec le modèle d'embeddings de la cible et leurs entités fusionnées avec celles de la cible.\nDocuments dont l'identifiant existe déjà dans la cible : remplacer ceux de la cible.\nLes réglages, directives et modèles mentaux de la source ne sont PAS copiés. Les observations de la cible seront mises à jour par sa prochaine consolidation (appels LLM).\n« source-1 » sera ensuite SUPPRIMÉE, et son identifiant mènera à « target.2 ».";
  const result = advancedConfirmationMessage('Fusionner « source-1 » dans « target.2 » ?', body);
  assert.match(result, /from “source-1” \(1 234 facts\).*“target.2” \(87 facts\)/);
  assert.match(result, /replace the target documents/);
  assert.match(result, /NOT copied/);
  assert.match(result, /next consolidation \(LLM calls\)/);
  assert.match(
    result,
    /“source-1” will then be DELETED, and its identifier will point to “target.2”/,
  );
  const keep = body.replace(
    '« source-1 » sera ensuite SUPPRIMÉE, et son identifiant mènera à « target.2 ».',
    '« source-1 » est conservée.',
  );
  assert.match(
    advancedConfirmationMessage('Fusionner « source-1 » dans « target.2 » ?', keep),
    /“source-1” will be kept/,
  );
  const remove = body.replace(', et son identifiant mènera à « target.2 »', '');
  assert.match(
    advancedConfirmationMessage('Fusionner « source-1 » dans « target.2 » ?', remove),
    /“source-1” will then be DELETED/,
  );
});

test('changer un identifiant conserve les deux variantes et avertit des écritures perdues', () => {
  setLanguage('en');
  const start =
    '1. La banque est copiée vers « next » (7 faits, réglages, directives, webhooks, journaux) — sans appel LLM.\n2. « prev » est supprimée.\n';
  const end =
    "\n\nPendant l'opération, une écriture envoyée à « prev » peut être perdue : arrêtez les agents qui l'utilisent.\nPour seulement changer ce qui est affiché, préférez « Nom affiché » ou « Alias affiché ».";
  const alias = advancedConfirmationMessage(
    "Changer l'identifiant « prev » en « next » ?",
    start +
      '3. « prev » devient un alias de « next » : les clients existants continuent de fonctionner.' +
      end,
  );
  assert.match(alias, /“prev” will become an alias for “next”/);
  assert.match(alias, /may be lost/);
  const noAlias = advancedConfirmationMessage(
    "Changer l'identifiant « prev » en « next » ?",
    start + '3. Les clients qui utilisent « prev » devront être mis à jour.' + end,
  );
  assert.match(noAlias, /Clients using “prev” will need to be updated/);
});

test('l’installation service conserve chemins et empreinte, et traduit ses effets', () => {
  setLanguage('en');
  const body =
    "Script exécuté : /Users/example/launch.sh\nEmpreinte SHA-256 : a1b2c3…\nAgent launchd : /Users/example/agent.plist\nJournal : /Users/example/server.log\nDémarrage à l'ouverture de session : oui\nLe script sera rendu exécutable pour vous (chmod u+x).\nLe service en cours sera redémarré avec cette configuration.\n\nCe script s'exécutera avec vos droits. N'approuvez qu'un fichier dont vous connaissez le contenu.";
  const result = advancedConfirmationMessage('Installer le service Hindsight ?', body);
  assert.match(result, /Script to run: \/Users\/example\/launch.sh/);
  assert.match(result, /SHA-256 fingerprint: a1b2c3…/);
  assert.match(result, /Start at login: yes/);
  assert.match(result, /running service will restart/);
  assert.match(result, /run with your permissions/);
});

test('une commande personnalisée et les messages de commit sont conservés exactement', () => {
  setLanguage('en');
  const command = 'echo "Enregistrer le script de lancement ?"\nprintf "%s" "texte utilisateur"';
  const body =
    'Commande exécutée sur ce Mac :\n' +
    command +
    "\n\nLes requêtes en cours seront interrompues ; les opérations en file seront reprises par le serveur à son redémarrage. L'app attend ensuite que l'API réponde puis teste les LLM.";
  assert.ok(
    advancedConfirmationMessage('Redémarrer le serveur Hindsight ?', body).includes(
      '\n' + command + '\n',
    ),
  );
  const commits = '  abc123  Enregistrer le script de lancement ? — Auteur, 2026-11-04';
  const update =
    'Dépôt : https://example.invalid/repo.git\nBranche : main → abc123\n1 commit(s) :\n' +
    commits +
    "\nCe code sera compilé puis exécuté sur ce Mac, avec vos droits. N'acceptez que des commits d'une source de confiance.\nL'app sera remplacée ; il suffira ensuite de la relancer.";
  const result = advancedConfirmationMessage('Installer la mise à jour ?', update);
  assert.match(result, /Repository: https:\/\/example.invalid\/repo.git/);
  assert.ok(result.includes(commits));
  assert.match(result, /with your permissions/);
});

test('la langue française et tout contenu de structure inconnue restent inchangés', () => {
  const message = 'Texte libre : Enregistrer le script de lancement ?';
  setLanguage('en');
  assert.equal(
    advancedConfirmationMessage('Supprimer la directive « exemple » ?', message),
    message,
  );
  assert.equal(advancedConfirmationMessage('Installer le service Hindsight ?', message), message);
  setLanguage('fr');
  assert.equal(advancedConfirmationMessage('Installer la mise à jour ?', message), message);
});
