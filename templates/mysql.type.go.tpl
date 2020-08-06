{{- $short := (shortname .Name "err" "res" "sqlStr" "db" "XOLog") -}}
{{- $table := (schema .Schema .Table.TableName) -}}
{{- if .Comment -}}
// {{ .Comment }}
{{- else -}}
// {{ .Name }} represents a row from '{{ $table }}'.
{{- end }}
type {{ .Name }} struct {
{{- range .Fields }}
	{{ .Name }} {{ retype .Type }} `json:"{{ .Col.ColumnName }}"` // {{ .Col.ColumnName }}
{{- end }}
{{- if .PrimaryKey }}

	// xo fields
	_exists, _deleted bool
{{ end }}
}

{{ if .PrimaryKey }}
// Exists determines if the {{ .Name }} exists in the database.
func ({{ $short }} *{{ .Name }}) Exists() bool {//{{  .Table.TableName  }}
	return {{ $short }}._exists
}

// Deleted provides information if the {{ .Name }} has been deleted from the database.
func ({{ $short }} *{{ .Name }}) Deleted() bool {
	return {{ $short }}._deleted
}

// Get table name
func Get{{  .Name  }}TableName(key... interface{}) (string, error) {
    schema := "{{  .Schema  }}"
    schema = strings.TrimSuffix(schema, "_dev")
    schema = strings.TrimSuffix(schema, "_pre")
    schema = strings.TrimSuffix(schema, "_test")
    env := os.Getenv("RUNTIME_ENV")
    if env != "prod" {
        schema = schema + "_" + env
    }
    tableName, err := components.M.GetTable(schema,"{{  .Table.TableName  }}", key...)
    if err != nil {
        return "", err
    }
	return tableName, nil
}

func ({{ $short }} *{{ .Name }}) GetTableName(key... interface{}) (string, error) {
    schema := "{{  .Schema  }}"
    schema = strings.TrimSuffix(schema, "_dev")
    schema = strings.TrimSuffix(schema, "_pre")
    schema = strings.TrimSuffix(schema, "_test")
    env := os.Getenv("RUNTIME_ENV")
    if env != "prod" {
        schema = schema + "_" + env
    }
    tableName, err := components.M.GetTable(schema,"{{  .Table.TableName  }}", key...)
    if err != nil {
        return "", err
    }
	return tableName, nil
}


// Insert inserts the {{ .Name }} to the database.
func ({{ $short }} *{{ .Name }}) Insert(ctx context.Context, key... interface{}) error {
	var err error
    var dbConn *sql.DB

	// if already exist, bail
	if {{ $short }}._exists {
		return errors.New("insert failed: already exists")
	}

    tx, err := components.M.GetConnFromCtx(ctx)
    if err != nil {
        dbConn, err = components.M.GetMasterConn()
        if err != nil {
       		return err
       	}
    }

    tableName, err := Get{{  .Name  }}TableName(key...)
    if err != nil {
        return err
    }


{{ if .Table.ManualPk  }}
	{{with .PrimaryKey }}
	//set primary key
        {{ $short }}.{{ .Name }} = {{ retype .Type }}(components.GetId())
    {{- end }}

	// sql insert query, primary key must be provided
     sqlStr := `INSERT INTO `+ tableName +
	    ` (` +
		`{{ colnames .Fields }}` +
		`) VALUES (` +
		`{{ colvals .Fields }}` +
		`)`

	// run query
	utils.GetTraceLog(ctx).Debug("DB", zap.String("SQL", fmt.Sprint(sqlStr, {{ fieldnames .Fields $short }})))
	if tx != nil {
	    _, err = tx.Exec(sqlStr, {{ fieldnames .Fields $short }})
	} else {
	    _, err = dbConn.Exec(sqlStr, {{ fieldnames .Fields $short }})
	}
{{ else }}
    {{ $short }}.ID = components.GetId()
	// sql insert query, primary key provided by autoincrement
	sqlStr := `INSERT INTO `+ tableName +
        ` (` +
		`{{ colnames .Fields .PrimaryKey.Name }}` +
		`) VALUES (` +
		`{{ colvals .Fields .PrimaryKey.Name }}` +
		`)`

	// run query
	utils.GetTraceLog(ctx).Debug("DB", zap.String("SQL", fmt.Sprint(sqlStr, {{ fieldnames .Fields $short .PrimaryKey.Name }})))
	if tx != nil {
    	_, err = tx.Exec(sqlStr, {{ fieldnames .Fields $short .PrimaryKey.Name }})
    } else {
    	_, err = dbConn.Exec(sqlStr, {{ fieldnames .Fields $short .PrimaryKey.Name }})
    }
{{ end }}

    if err != nil {
        return err
    }

    // set existence
    {{ $short }}._exists = true

	return nil
}

{{ if ne (fieldnamesmulti .Fields $short .PrimaryKeyFields) "" }}
	// Update updates the {{ .Name }} in the database.
func ({{ $short }} *{{ .Name }}) Update(ctx context.Context, key... interface{}) error {
	var err error
	var dbConn *sql.DB

	// if deleted, bail
	if {{ $short }}._deleted {
		return errors.New("update failed: marked for deletion")
	}

    tx, err := components.M.GetConnFromCtx(ctx)
    if err != nil {
        dbConn, err = components.M.GetMasterConn()
        if err != nil {
            return err
        }
    }

    tableName, err := Get{{  .Name  }}TableName(key...)
    if err != nil {
        return err
    }

    // sql query with composite primary key
	sqlStr := `UPDATE ` + tableName + ` SET ` +
			`{{ colnamesquerymulti .Fields ", " 0 .PrimaryKeyFields }}` +
			` WHERE id = ?`

	// run query
	utils.GetTraceLog(ctx).Debug("DB", zap.String("SQL", fmt.Sprint(sqlStr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ $short }}.ID)))
	if tx != nil {
	    _, err = tx.Exec(sqlStr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ $short }}.ID)
	} else {
	    _, err = dbConn.Exec(sqlStr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ $short }}.ID)
	}
	return err
}

// Save saves the {{ .Name }} to the database.
func ({{ $short }} *{{ .Name }}) Save(ctx context.Context) error {
	if {{ $short }}.Exists() {
		return {{ $short }}.Update(ctx)
	}

	return {{ $short }}.Insert(ctx)
}
{{ else }}
	// Update statements omitted due to lack of fields other than primary key
{{ end }}

// Delete deletes the {{ .Name }} from the database.
func ({{ $short }} *{{ .Name }}) Delete(ctx context.Context, key... interface{}) error {
	var err error
	var dbConn *sql.DB

	// if deleted, bail
	if {{ $short }}._deleted {
		return nil
	}

    tx, err := components.M.GetConnFromCtx(ctx)
    if err != nil {
       dbConn, err = components.M.GetMasterConn()
       if err != nil {
           return err
       }
    }

    tableName, err := Get{{  .Name  }}TableName(key...)
    if err != nil {
        return err
    }

    // sql query with composite primary key
    sqlStr := `UPDATE ` + tableName + ` SET is_del = ? WHERE id = ?`

    // run query
    utils.GetTraceLog(ctx).Debug("DB", zap.String("SQL", fmt.Sprint(sqlStr, utils.DELETED, {{ $short }}.ID)))
    if tx != nil {
        _, err = tx.Exec(sqlStr, utils.DELETED, {{ $short }}.ID)
    } else {
        _, err = dbConn.Exec(sqlStr, utils.DELETED, {{ $short }}.ID)
    }

    if err != nil {
        return err
    }

	// set deleted
	{{ $short }}._deleted = true

	return nil
}
//*************Generate by xo******************
{{- end }}

func Get{{ .Name }}ScanField ( {{ $short }}  *{{ .Name }}) []interface{} {
    return scan{{ .Name }}(
        {{- range .Fields }}
            &{{ $short }}.{{ .Name }},
        {{- end }}
        )
}

func Get{{ .Name }}FieldStringSlice () []string {
    return strings.Split(`{{colnames .Fields}}`,",")
}

func Get{{ .Name }}FieldString () string {
    return `{{colnames .Fields}}`
}

func scan{{ .Name }} ( {{ $short }} ...interface{}) []interface{} {
    return {{ $short }}
}


func ({{ $short }} *{{ .Name }}) GetScanField () []interface{} {
    return {{ $short }}.scan(
        {{- range .Fields }}
            &{{ $short }}.{{ .Name }},
        {{- end }}
        )
}

func ({{ $short }} *{{ .Name }}) GetFieldStringSlice () []string {
    return strings.Split(`{{colnames .Fields}}`,",")
}

func ({{ $short }} *{{ .Name }}) GetFieldString () string {
    return `{{colnames .Fields}}`
}

func ({{ $short }} *{{ .Name }}) scan ( i ...interface{}) []interface{} {
    return i
}

func ({{ $short }} *{{ .Name }}) New () interface{} {
    return &{{ .Name }}{
        _exists: true,
    }
}

func ({{ $short }} *{{ .Name }}) GetInsertValues() []interface{} {
    {{ if .PrimaryKey }}
            {{- $pkName := (.PrimaryKey.Name) -}}
            return scan{{ .Name }}(
                {{- range .Fields }}
                    {{ if eq (.Name) $pkName }} nil, {{- else }} {{ $short }}.{{ .Name }}, {{- end }}
                {{- end }}
                )
        {{- else }}
            return scan{{ .Name }}(
                {{- range .Fields }}
                    {{ $short }}.{{ .Name }},
                {{- end }}
                )
        {{- end }}
}

func Get{{ .Name }}InsertValues ( {{ $short }}  *{{ .Name }}) []interface{} {
    {{ if .PrimaryKey }}
        {{- $pkName := (.PrimaryKey.Name) -}}
        return scan{{ .Name }}(
            {{- range .Fields }}
                {{ if eq (.Name) $pkName }} nil, {{- else }} {{ $short }}.{{ .Name }}, {{- end }}
            {{- end }}
            )
    {{- else }}
        return scan{{ .Name }}(
            {{- range .Fields }}
                {{ $short }}.{{ .Name }},
            {{- end }}
            )
    {{- end }}
}




