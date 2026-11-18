// Cria (ou sincroniza a senha de) um usuário dedicado ao mongodump.
// Papel 'backup' do MongoDB: somente leitura necessária para cópias.
// Imprime "created" ou "exists" para o Ansible decidir se houve mudança.
const fs = require('fs');
const read = (name) => fs.readFileSync('/run/secrets/' + name, 'utf8').trim();

const admin = db.getSiblingDB('admin');
if (!admin.auth('admin', read('mongo_root_password')).ok) quit(1);

const pwd = read('mongo_backup_password');
if (admin.getUser('backup')) {
  admin.updateUser('backup', { pwd });
  print('exists');
} else {
  admin.createUser({ user: 'backup', pwd, roles: [{ role: 'backup', db: 'admin' }] });
  print('created');
}
