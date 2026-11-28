# Politique de confidentialité de Rayon

_Dernière mise à jour : 27 novembre 2026_

_En cas de divergence entre les versions linguistiques de cette politique, la version anglaise prévaut._

Rayon est un client SSH et serveur. Vos serveurs, identités, clés, mots de passe, extraits, redirections de ports, fichiers et sessions de terminal restent sur vos appareils, ainsi que dans votre propre compte iCloud si vous activez la synchronisation iCloud. Personne d’autre ne peut les lire, y compris les développeurs de Rayon.

Les seules données que Rayon envoie à ses développeurs sont des diagnostics anonymes et des décomptes d’utilisation. Vous choisissez leur étendue dans Réglages › À propos › Diagnostics et utilisation, et vous pouvez les désactiver à tout moment.

## 1. Ce que chaque niveau envoie

- **Désactivé (0) :** rien. Rayon n’établit aucune connexion avec son serveur de télémétrie.
- **Rapports de plantage (1) :** les rapports de plantage et de blocage de MetricKit d’Apple, débarrassés sur votre appareil de tout message et de tout nom. Il ne reste que le type de problème, les codes numériques d’exception et de signal, une catégorie pour le motif de l’arrêt, un nom d’exception système issu d’une liste fixe, une durée approximative du blocage, et des piles d’appels sous forme d’identifiants binaires et de décalages au sein de Rayon et du système.
- **Rapports de plantage et utilisation (2) :** le niveau 1, plus un rapport par jour contenant des décomptes d’utilisation des fonctionnalités, chacun arrondi à une tranche (0, 1, 2–5, 6–20, 21–100, plus de 100). Les fonctionnalités comptées sont les sessions de terminal ouvertes, les navigateurs de fichiers ouverts, les transferts de fichiers, l’éditeur, les moniteurs, les sessions VNC et UU Remote, les extraits exécutés et les redirections de ports par type. Le rapport compte aussi les résultats de connexion (par exemple réussite, authentification refusée, délai dépassé, connexion refusée, clé d’hôte non approuvée, hôte introuvable) et indique quelles méthodes d’authentification ont été utilisées ce jour-là (mot de passe, clé, agent). Il contient également les types de clés parmi vos identités (Ed25519, ECDSA, RSA), des tranches pour le nombre de serveurs et d’identités enregistrés, l’indication de l’activation ou non de la synchronisation iCloud, d’un thème de terminal personnalisé et du masquage des adresses, ainsi qu’une tranche pour le nombre de jours d’utilisation de Rayon au cours des 28 derniers jours.
- **Diagnostics détaillés (3) :** le niveau 2, plus, environ un jour sur dix : des tranches pour la durée d’authentification, la famille de système d’exploitation des serveurs que vous surveillez (Linux, macOS, BSD, autre), et les mesures de performance quotidiennes d’Apple (temps de lancement, durée des blocages, pic de mémoire, temps CPU, écritures sur disque), chacune arrondie à une tranche.

Chaque rapport contient aussi la version de Rayon, la version majeure et mineure du système d’exploitation, la plateforme (macOS, iOS ou iPadOS), la catégorie d’appareil (Mac avec puce Apple, Mac Intel, iPhone ou iPad), la langue de l’app (anglais, chinois simplifié, chinois traditionnel ou autre), la manière dont Rayon a été installé (App Store, TestFlight ou téléchargement direct) et un groupe de régions approximatif (EEE/Royaume-Uni/Suisse, Chine continentale ou autre) déduit du pays de votre compte App Store.

Vous pouvez consulter les rapports exacts dans Réglages › À propos › Diagnostics et utilisation › Voir ce qui est envoyé…

## 2. Ce qui n’est jamais envoyé

Quel que soit le niveau, Rayon n’envoie jamais : les noms, adresses, ports ou noms d’utilisateur des serveurs ; les mots de passe, phrases de passe, clés, empreintes de clés ou commentaires de clés ; les commandes, extraits, entrées ou sorties du terminal, ni le presse-papiers ; les noms, chemins ou tailles de fichiers ; les bannières ou chaînes de version distantes ; les messages d’erreur ; les variables d’environnement ; les identifiants iCloud ou de compte ; les identifiants d’appareil (tels que l’IDFV, l’IDFA ou les numéros de série) ; l’heure exacte, le fuseau horaire, la taille de l’écran, le type de réseau ou le nom du réseau Wi-Fi ; ni votre position.

## 3. Comment les données sont conservées

- Les rapports ne comportent **aucun identifiant** de vous, de votre appareil ou de votre installation. Chaque rapport porte un nombre aléatoire servant uniquement à écarter un doublon s’il est envoyé deux fois ; il est supprimé dans un délai de trois jours.
- Le serveur **ne lit ni ne conserve jamais votre adresse IP** ni la chaîne du navigateur/User-Agent, et ne tient aucun journal des requêtes.
- Les dates sont conservées au jour près. Chaque rapport est ajouté aux totaux quotidiens dès son arrivée, puis supprimé. Les éléments relatifs aux plantages et aux blocages sont conservés **90 jours** à des fins de diagnostic, puis supprimés.
- Les totaux portant sur moins de **10** rapports ne sont jamais affichés ni exportés.
- Comme rien ne vous identifie, un rapport ne peut pas vous être rattaché par la suite. Les données ne servent pas à vous suivre, ne sont pas vendues et ne sont partagées qu’avec le sous-traitant indiqué ci-dessous.

## 4. Qui les traite

- **Cloudflare, Inc.** exploite le serveur de télémétrie (un Cloudflare Worker et sa base de données D1, située dans la région Asie-Pacifique) en tant que sous-traitant de Rayon. Le réseau de Cloudflare voit nécessairement la connexion, y compris son adresse IP, lorsqu’il l’achemine ; le serveur de Rayon ne la lit pas.
- **GitHub, Inc.** répond à « Rechercher des mises à jour… » dans l’app Mac, qui interroge l’API publique de GitHub sur la dernière version uniquement lorsque vous choisissez cette commande. GitHub voit cette requête dans le cadre de sa propre déclaration de confidentialité.
- **Apple** fournit MetricKit, la synchronisation iCloud (vos données dans votre propre compte iCloud) et l’App Store, dans le cadre de la politique de confidentialité d’Apple.
- Les services auxquels vous connectez vous-même Rayon, tels que vos serveurs, Cloudflare Access ou UU Remote, reçoivent ce que vous leur envoyez dans le cadre de leurs propres politiques.

## 5. Modifier ou retirer votre choix

Ouvrez Réglages › À propos › Diagnostics et utilisation et déplacez le curseur. La modification prend effet immédiatement. Abaisser le niveau supprime, sur cet appareil, les rapports et décomptes en attente que le nouveau niveau n’enverrait pas ; Désactivé arrête en outre la transmission de MetricKit à Rayon et supprime la file d’attente des rapports. « Supprimer les rapports en attente » et « Réinitialiser l’historique d’activité » dans Voir ce qui est envoyé… effacent le reste. Le réglage est conservé sur chaque appareil et n’est jamais synchronisé.

Les rapports déjà envoyés ne peuvent pas être supprimés sur demande, car rien en eux n’indique à qui ils appartiennent (article 11 du RGPD).

## 6. Base légale

- **EEE, Royaume-Uni et Suisse :** votre consentement. Rien n’est envoyé tant que vous n’avez pas choisi « Partager des données anonymes », et vous pouvez retirer votre consentement à tout moment.
- **Chine continentale :** rien n’est envoyé tant que vous n’avez pas vu l’avis et la présente politique. Les données sont des informations anonymisées au sens de la loi sur la protection des informations personnelles (article 4, article 73).
- **Ailleurs :** notre intérêt légitime à corriger les bogues et à améliorer Rayon, au moyen de données anonymes dès leur conception. Le niveau 2 est le niveau par défaut, et l’avis affiché au premier lancement vous en informe.

Rayon ne s’adresse pas aux enfants et ne collecte pas sciemment de données les concernant.

## 7. Contact et modifications

Questions et demandes : https://github.com/mizorewww/Rayon/issues

Si ce que Rayon envoie venait à changer, la présente politique, le schéma dans le code source et l’étiquette de confidentialité de l’App Store changeront dans la même version.
