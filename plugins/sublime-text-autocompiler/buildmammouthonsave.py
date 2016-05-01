# REQUIREMENTS: npm install -g mammouth
# USAGE: Files must have a .mammouth or .mmt suffix

import sublime, sublime_plugin,os,sys
from os.path import dirname, realpath

class BuildMammouthOnSave(sublime_plugin.EventListener):
 
  def on_post_save(self, view):
    mammouthFile = view.file_name()
    filename, file_extension = os.path.splitext(mammouthFile)
    if sublime.platform() == "windows" or sublime.platform() == "win32":
      file_extension = file_extension.encode(sys.getfilesystemencoding())
    if file_extension == ".mammouth" or file_extension == ".mmt":
      print("Compiling: " + mammouthFile)
      if sublime.platform() == "windows":
        os.system("mammouth -c " + mammouthFile)
      else:
        view.window().run_command('exec',{'cmd': ["/usr/local/bin/mammouth", "-c", mammouthFile] })

# REFERENCES
# http://www.purplebeanie.com/Development/automatically-run-build-on-save-in-sublime-text-2.html