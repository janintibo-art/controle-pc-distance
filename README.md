# Controle PC Distance - V2

Application Flutter Windows (.exe) et Android (.apk) pour le controle a distance de son propre PC.

## V2 : fondation de connexion sans Tailscale

- **Fonctionnel :** interface Windows/Android, serveur de statut local sur Windows, detection des IP privees, code aleatoire de jumelage, verification par defi HMAC-SHA256 (le secret n'est pas transmis), sauvegarde des parametres Android.
- **Pas encore fonctionnel :** affichage/controle du bureau, transferts et telechargements, acces via Internet, relais NAT et integration de la carte Tuya A3.
- **Securite :** test de liaison seulement sur Wi-Fi prive. HTTP local ne chiffre pas les informations transmises : ne pas employer sur un reseau Wi-Fi public et **ne pas ouvrir le port 47186 sur la box Internet**. L'acces Internet et les commandes sensibles necessiteront un tunnel chiffre et une authentification robuste.

## Utilisation

1. Installer Windows et Android depuis la Release v2.
2. Connecter les deux appareils au **meme Wi-Fi prive**.
3. Ouvrir le programme Windows, relever son adresse IPv4 privee et son code, activer le serveur.
4. Sur Android, entrer l'adresse et le code, puis *Tester la connexion*.
5. Si besoin, autoriser le programme sur le pare-feu Windows pour les reseaux prives exclusivement.

**La carte Tuya A3 n'a pas besoin d'etre installee pour ce premier test.** Lors de son installation, il faudra verifier l'alimentation de veille, les branchements du bouton Power et la methode de pilotage disponible (Tuya/Smart Life ou protocole local). Ne pas supposer que le protocole local est accessible avant le test.

## Construction

Le workflow GitHub Actions compile un APK Android et un EXE Windows (distribue avec ses DLL dans un ZIP) puis publie les deux en Releases.

## V3 — diagnostic de connexion

Depuis Android, la verification affiche le nom du PC, la duree de la requete et la date du dernier test. Depuis Windows, le bouton permet de copier l’adresse IP locale. Cette version ne transmet pas encore video, souris, clavier ou fichiers. La communication HTTP locale sert exclusivement a authentifier le diagnostic : ne pas exposer le port 47186 sur Internet.


## V4 — Aperçu du bureau sur Wi-Fi local

Dans l'EXE Windows : activer le serveur, puis aller dans **Bureau** et autoriser les captures. Dans l'APK : saisir l'IP privée et le code, tester la connexion, puis ouvrir **Bureau** et demander une capture. Rafraîchissement facultatif toutes les 3 secondes.

**Sécurité :** prototype uniquement sur réseau Wi-Fi privé de confiance, images JPEG transmises en HTTP **sans chiffrement**. Éviter impérativement toute information sensible à l'écran. Ne pas ouvrir de ports sur Internet. Une version TLS avec épinglage du certificat, une vraie diffusion et les contrôles souris/clavier sont nécessaires avant utilisation distante.
