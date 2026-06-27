const escapeCsv = (value) => {
  const stringValue = value === null || value === undefined ? '' : String(value);
  return `"${stringValue.replace(/"/g, '""')}"`;
};

function toCsv(columns, rows) {
  const header = columns.map((c) => escapeCsv(c.label)).join(',');
  const body = rows
    .map((row) => columns.map((c) => escapeCsv(row[c.key])).join(','))
    .join('\n');
  return `${header}\n${body}`;
}

module.exports = { escapeCsv, toCsv };
