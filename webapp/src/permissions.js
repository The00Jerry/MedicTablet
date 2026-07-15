'use strict';
// Rechte-Bundles je Grade – identisch zum In-Game-Tablet (config/permissions.lua).
// Discord-Rollen werden ueber config.json (roles.map) auf einen Grade abgebildet.

const GRADE_PERMS = {
  0: ['tablet.open', 'patient.search', 'patient.view', 'pricelist.view', 'insurance.patient.view'],
  1: ['treatment.create', 'patient.edit'],
  2: ['treatment.edit', 'treatment.archive', 'invoice.create', 'discount.grant', 'notes.internal.view'],
  3: ['invoice.cancel', 'staff.view', 'audit.view', 'insurance.failed.view', 'insurance.retry'],
  4: ['admin.full'],
};

const ALL_PERMS = [
  'tablet.open','patient.search','patient.view','patient.edit','treatment.create','treatment.edit',
  'treatment.archive','notes.internal.view','invoice.create','invoice.cancel','discount.grant',
  'pricelist.view','pricelist.edit','insurance.patient.view','insurance.manage','insurance.failed.view',
  'insurance.retry','staff.view','audit.view','settings.edit','admin.full',
];

function permsForGrade(grade) {
  const set = {};
  for (let g = 0; g <= grade; g++) {
    (GRADE_PERMS[g] || []).forEach((p) => (set[p] = true));
  }
  return set;
}

// memberRoles: Array von Discord-Role-IDs des Nutzers
// roles: config.roles = { adminRoleIds:[], map:[{roleId, grade, label}] }
function permsForRoles(memberRoles, roles) {
  const set = {};
  let topLabel = null;
  const rolesSet = new Set(memberRoles || []);

  (roles.adminRoleIds || []).forEach((rid) => {
    if (rolesSet.has(rid)) { set['admin.full'] = true; topLabel = 'Administrator'; }
  });

  let maxGrade = -1;
  (roles.map || []).forEach((m) => {
    if (rolesSet.has(m.roleId)) {
      Object.assign(set, permsForGrade(m.grade));
      if (m.grade > maxGrade) { maxGrade = m.grade; topLabel = m.label || ('Grade ' + m.grade); }
    }
  });

  return { perms: set, label: topLabel, hasAccess: Object.keys(set).length > 0 };
}

function has(perms, perm) {
  if (!perm) return true;
  if (perms['admin.full']) return true;
  return perms[perm] === true;
}

module.exports = { GRADE_PERMS, ALL_PERMS, permsForGrade, permsForRoles, has };
