module Y = Yojson
module S = Supjson
module N = Netclient_easy
module A2O = Additions_to_option
module A2L = ExtList.List
module B64 = Netencoding.Base64

type hbase_environment = {
  host : string;
  port : int;
  table : string;
}

let (>>=) : 'a option -> ('a -> 'b  option) -> 'b option = A2O.bind

let accept_json_header : (string * string) list = [("Accept", "application/json")]

let get_cell : Y.Basic.json -> (int * string * string) option = function
  | `Assoc [("Row",`List [`Assoc record])] ->
      A2O.safe_assoc "Cell" record >>= (fun cell_json ->
      S.from_list cell_json        >>= (fun cell ->
      A2O.option_of_list cell      >>= (fun cell_option ->
      S.from_assoc cell_option     >>= (fun c ->
      let search_c_for key = A2O.safe_assoc key c in
      search_c_for "timestamp"     >>= (fun timestamp_json ->
      S.from_int timestamp_json    >>= (fun timestamp ->
      search_c_for "column"        >>= (fun column_json ->
      S.from_string column_json    >>= (fun column ->
      search_c_for "$"             >>= (fun contents_json ->
      S.from_string contents_json  >>= (fun contents ->
      Some (timestamp, B64.decode column, B64.decode contents)))))))))))
  | _ -> None

(* NOTE: According to http://wiki.apache.org/hadoop/Hbase/Stargate (search for
 * "Cell or Row Query (Multiple Values)") '?v=1' always returns the most recent
 * cell *)
let get (environment : hbase_environment) (row : string) : (int * string * string) option =
  let uri = "http://" ^ environment.host ^ ":" ^ (string_of_int environment.port) ^ "/" ^ environment.table ^ "/" ^ row ^ "?v=1" in
  (N.http_get_with_header uri accept_json_header) >>= (fun response ->
  get_cell (Y.Basic.from_string response))

let get_rows (environment : hbase_environment) (rows : string list) : (int * string * string) option list =
  let uris = A2L.combine
               (A2L.map (fun row -> "http://" ^ environment.host ^ ":" ^ (string_of_int environment.port) ^ "/" ^ environment.table ^ "/" ^ row ^ "?v=1") rows)
               (A2L.make (List.length rows) accept_json_header) in
  A2L.map
    (fun oresponse ->
       oresponse >>= (fun response -> get_cell (Y.Basic.from_string response)))
    (N.http_gets_with_headers uris)

let get_rows_simple (environment : hbase_environment) (rows : string list) : (int * string * string) list =
  A2O.cat_somes (get_rows environment rows)

let connect (host : string) (port : int) (table : string) : hbase_environment =
  { host = host
  ; port = port
  ; table = table }
