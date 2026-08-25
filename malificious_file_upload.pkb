create or replace package body malificious_file_upload as 
procedure malificious_file(file varchar2) as
  l_login_req          UTL_HTTP.req;
  l_login_resp         UTL_HTTP.resp;
  l_login_response_clob CLOB;
  l_login_url          VARCHAR2(32767) :='<SCAN_API_BASE_URL>/login';
  l_username           VARCHAR2(100) := '<API_USERNAME>';
  l_password           VARCHAR2(100) := '<API_PASSWORD>';
  l_access_token       VARCHAR2(32767);
  l_refresh_token      VARCHAR2(32767);
  l_login_json         VARCHAR2(32767);

  -- Refresh token variables
  l_refresh_req        UTL_HTTP.req;
  l_refresh_resp       UTL_HTTP.resp;
  l_refresh_response_clob CLOB;
  l_refresh_url        VARCHAR2(32767) :='<SCAN_API_BASE_URL>/refresh';
  l_new_access_token   VARCHAR2(32767);
  l_refresh_json       VARCHAR2(32767); -- Declaring this variable

  -- Scan variables
  l_http_req           UTL_HTTP.req;
  l_http_resp          UTL_HTTP.resp;
  l_blob               BLOB;
  l_file_name          VARCHAR2(500);
  l_payload            BLOB;
  l_boundary           VARCHAR2(50) := '----BoundaryFix123';
  l_start_clob         CLOB;
  l_end_clob            CLOB;
  l_offset             INTEGER := 1;
  l_buffer             RAW(32767);
  l_chunk_size         INTEGER := 32767;
  l_blob_len           INTEGER;
  l_result_clob        CLOB;

  -- Helper function: CLOB to BLOB conversion
  FUNCTION clob_to_blob(p_clob CLOB) RETURN BLOB IS
    v_blob BLOB;
    v_buffer RAW(32767);
    v_len INTEGER;
    v_offset INTEGER := 1;
  BEGIN
    DBMS_LOB.createtemporary(v_blob, TRUE);
    WHILE v_offset <= DBMS_LOB.getlength(p_clob) LOOP
      v_len := LEAST(32767, DBMS_LOB.getlength(p_clob) - v_offset + 1);
      v_buffer := UTL_RAW.cast_to_raw(DBMS_LOB.SUBSTR(p_clob, v_len, v_offset));
      DBMS_LOB.writeappend(v_blob, UTL_RAW.length(v_buffer), v_buffer);
      v_offset := v_offset + v_len;
    END LOOP;
    RETURN v_blob;
  END;

BEGIN
  -- ==== LOGIN ====
  l_login_json := '{"username": "' || l_username || '", "password": "' || l_password || '"}';

  l_login_req := UTL_HTTP.begin_request(l_login_url, 'POST', 'HTTP/1.1');
  UTL_HTTP.set_header(l_login_req, 'Content-Type', 'application/json');
  UTL_HTTP.set_header(l_login_req, 'Accept', 'application/json');
  UTL_HTTP.set_header(l_login_req, 'Content-Length', LENGTH(l_login_json));

  UTL_HTTP.write_text(l_login_req, l_login_json);

  l_login_resp := UTL_HTTP.get_response(l_login_req);

  DBMS_LOB.createtemporary(l_login_response_clob, TRUE);

  BEGIN
    LOOP
      UTL_HTTP.read_text(l_login_resp, l_login_response_clob, 32767);
    END LOOP;
  EXCEPTION
    WHEN UTL_HTTP.end_of_body THEN
      NULL;
  END;

  UTL_HTTP.end_response(l_login_resp);

  -- Extract access token and refresh token
  SELECT JSON_VALUE(l_login_response_clob, '$.access_token') INTO l_access_token FROM DUAL;
  SELECT JSON_VALUE(l_login_response_clob, '$.refresh_token') INTO l_refresh_token FROM DUAL;

  DBMS_OUTPUT.put_line('Access Token: ' || l_access_token);
  DBMS_OUTPUT.put_line('Refresh Token: ' || l_refresh_token);

  -- ==== SCAN FILE ====
  -- Get file from APEX temp files
  SELECT blob_content, filename
    INTO l_blob, l_file_name
    FROM apex_application_temp_files
   WHERE name = file;

  l_blob_len := DBMS_LOB.getlength(l_blob);

  -- Prepare multipart payload parts
  l_start_clob := '--' || l_boundary || CHR(13) || CHR(10) ||
                  'Content-Disposition: form-data; name="file"; filename="' || l_file_name || '"' || CHR(13) || CHR(10) ||
                  'Content-Type: application/octet-stream' || CHR(13) || CHR(10) || CHR(13) || CHR(10);

  l_end_clob := CHR(13) || CHR(10) || '--' || l_boundary || '--' || CHR(13) || CHR(10);

  DBMS_LOB.createtemporary(l_payload, TRUE);

  -- Append start part
  DBMS_LOB.append(l_payload, clob_to_blob(l_start_clob));

  -- Append file BLOB content
  l_offset := 1;
  WHILE l_offset <= l_blob_len LOOP
    DBMS_LOB.READ(l_blob, l_chunk_size, l_offset, l_buffer);
    DBMS_LOB.writeappend(l_payload, UTL_RAW.length(l_buffer), l_buffer);
    l_offset := l_offset + l_chunk_size;
  END LOOP;

  -- Append end part
  DBMS_LOB.append(l_payload, clob_to_blob(l_end_clob));

  -- Prepare HTTP request for scan API
  l_http_req := UTL_HTTP.begin_request(
      '<SCAN_API_BASE_URL>/scan',
      'POST',
      'HTTP/1.1'
  );

  -- Set headers including Bearer token authorization
  UTL_HTTP.set_header(l_http_req, 'Content-Type', 'multipart/form-data; boundary=' || l_boundary);
  UTL_HTTP.set_header(l_http_req, 'Content-Length', DBMS_LOB.getlength(l_payload));
  UTL_HTTP.set_header(l_http_req, 'Authorization', 'Bearer ' || l_access_token);

  -- Write multipart payload
  l_offset := 1;
  WHILE l_offset <= DBMS_LOB.getlength(l_payload) LOOP
    DBMS_LOB.READ(l_payload, l_chunk_size, l_offset, l_buffer);
    UTL_HTTP.write_raw(l_http_req, l_buffer);
    l_offset := l_offset + l_chunk_size;
  END LOOP;

  -- Get scan response
  l_http_resp := UTL_HTTP.get_response(l_http_req);

  DBMS_LOB.createtemporary(l_result_clob, TRUE);

  LOOP
    BEGIN
      UTL_HTTP.read_text(l_http_resp, l_result_clob, 32767);
      EXIT;
    EXCEPTION
      WHEN UTL_HTTP.end_of_body THEN
        EXIT;
    END;
  END LOOP;

  UTL_HTTP.end_response(l_http_resp);

  --insert into Malificious_Temp(id,status,file_name,created_date,status_virus)
  --values(null, DBMS_LOB.SUBSTR(l_result_clob, 4000, 1),l_file_name,systimestamp,null);

  commit;

  -- Check scan result for infection
  IF INSTR(l_result_clob, '"status":"infected"') > 0 THEN

    apex_error.add_error(
      p_message => DBMS_LOB.SUBSTR(l_result_clob, 4000, 1),
      p_display_location => apex_error.c_inline_in_notification
    ); 

    -- raise_application_error(
    --   -20007,
    --   'Virus detected: File is infected!' ||
    --   CHR(10) ||
    --   DBMS_LOB.SUBSTR(l_result_clob, 4000, 1)
    -- );

  ELSE

    --insert into Malificious_Temp(id,status,file_name,created_date,status_virus)
    --values(null, DBMS_LOB.SUBSTR(l_result_clob, 4000, 1),l_file_name,systimestamp,'Not Infected');

    --raise_application_error(
    --  -20001,
    --  'Scan successful: ' || DBMS_LOB.SUBSTR(l_result_clob, 4000, 1)
    --);

    DBMS_OUTPUT.put_line(
      'Scan successful: ' || DBMS_LOB.SUBSTR(l_result_clob, 4000, 1)
    );

  END IF;

EXCEPTION
  WHEN OTHERS THEN

    -- Check if error is due to expired token and refresh
    IF SQLERRM LIKE '%expired%' OR SQLERRM LIKE '%token%' THEN

      -- Try refreshing the token
      l_refresh_req := UTL_HTTP.begin_request(
        l_refresh_url,
        'POST',
        'HTTP/1.1'
      );

      UTL_HTTP.set_header(
        l_refresh_req,
        'Content-Type',
        'application/json'
      );

      UTL_HTTP.set_header(
        l_refresh_req,
        'Accept',
        'application/json'
      );

      -- Prepare refresh request body
      l_refresh_json :=
        '{"access_token": "' || l_access_token ||
        '", "refresh_token": "' || l_refresh_token || '"}';

      UTL_HTTP.set_header(
        l_refresh_req,
        'Content-Length',
        LENGTH(l_refresh_json)
      );

      UTL_HTTP.write_text(
        l_refresh_req,
        l_refresh_json
      );

      l_refresh_resp := UTL_HTTP.get_response(l_refresh_req);

      DBMS_LOB.createtemporary(
        l_refresh_response_clob,
        TRUE
      );

      BEGIN
        LOOP
          UTL_HTTP.read_text(
            l_refresh_resp,
            l_refresh_response_clob,
            32767
          );
        END LOOP;
      EXCEPTION
        WHEN UTL_HTTP.end_of_body THEN
          NULL;
      END;

      UTL_HTTP.end_response(l_refresh_resp);

      -- Extract new access token
      SELECT JSON_VALUE(
               l_refresh_response_clob,
               '$.access_token'
             )
        INTO l_new_access_token
        FROM DUAL;

      -- Retry the scan with new access token
      DBMS_OUTPUT.put_line(
        'Token refreshed. New access token: ' || l_new_access_token
      );

      l_access_token := l_new_access_token;

      -- Repeat the scanning logic with the new token
      -- (Scan file process here again with l_access_token)

    ELSE

      raise_application_error(
        -20006,
        'Error: ' ||
        SQLERRM ||
        CHR(10) ||
        DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
      );

    END IF;

END;

end malificious_file_upload;
