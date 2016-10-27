import sys, dropbox
inputfile = sys.argv[1]
token = sys.argv[2]

dbx = dropbox.Dropbox(token)

submitter = (dbx.files_get_metadata(inputfile).sharing_info.modified_by)

display_name = dbx.users_get_account(submitter).name.display_name
submitter_email = dbx.users_get_account(submitter).email

print submitter_email, display_name
