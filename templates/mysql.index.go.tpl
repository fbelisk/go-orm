{{- if not .Index.IsPrimary }}
{{- $short := (shortname .Type.Name "err" "sqlStr" "q" "res" .Fields) -}}
{{- $table := (schema .Schema .Type.Table.TableName) -}}
// {{ .FuncName }} retrieves a row from '{{ $table }}' as a {{ .Type.Name }}.
//
// Generated from index '{{ .Index.IndexName }}'.
    func {{ .FuncName }}(ctx context.Context, {{ goparamlist .Fields false true }}, key... interface{}) ({{ if not .Index.IsUnique }}[]{{ end }}*{{ .Type.Name }}, error) {
        var err error
        var dbConn *sql.DB

        tableName, err := Get{{  .Type.Name  }}TableName(key...)
        if err != nil {
            return nil, err
        }

        // sql query
        sqlStr := `SELECT ` +
            `{{ colnames .Type.Fields }} ` +
            `FROM ` + tableName +
            ` WHERE {{ colnamesquery .Fields " AND " }}` + ` AND is_del = ?`


        // run query
        utils.GetTraceLog(ctx).Debug("DB", zap.String("SQL", fmt.Sprint(sqlStr{{ goparamlist .Fields true false }}, utils.NOT_DELETED)))

        tx, err := components.M.GetConnFromCtx(ctx)
        if err != nil {
           dbConn, err = components.M.GetSlaveConn()
           if err != nil {
               return nil, err
           }
        }

    {{- if .Index.IsUnique }}
        {{ $short }} := {{ .Type.Name }}{
        {{- if .Type.PrimaryKey }}
            _exists: true,
        {{ end -}}
        }

        if tx != nil {
            err = tx.QueryRow(sqlStr{{ goparamlist .Fields true false }},utils.NOT_DELETED).Scan({{ fieldnames .Type.Fields (print "&" $short) }})
            if err != nil {
                return nil, err
            }
        } else {
            err = dbConn.QueryRow(sqlStr{{ goparamlist .Fields true false }},utils.NOT_DELETED).Scan({{ fieldnames .Type.Fields (print "&" $short) }})
            if err != nil {
                return nil, err
            }
        }

        return &{{ $short }}, nil
    {{- else }}
        var queryData *sql.Rows
        if tx != nil {
            queryData, err = tx.Query(sqlStr{{ goparamlist .Fields true false }},utils.NOT_DELETED)
            if err != nil {
                return nil, err
            }
        } else {
            queryData, err = dbConn.Query(sqlStr{{ goparamlist .Fields true false }},utils.NOT_DELETED)
            if err != nil {
                return nil, err
            }
        }

        defer queryData.Close()

        // load results
        res := make([]*{{ .Type.Name }}, 0)
        for queryData.Next() {
            {{ $short }} := {{ .Type.Name }}{
            {{- if .Type.PrimaryKey }}
                _exists: true,
            {{ end -}}
            }

            // scan
            err = queryData.Scan({{ fieldnames .Type.Fields (print "&" $short) }})
            if err != nil {
                return nil, err
            }

            res = append(res, &{{ $short }})
        }

        return res, nil
    {{- end }}
    }
//*************Generate by xo******************
{{- end }}
