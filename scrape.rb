require "net/http"
require "nokogiri"
require "json"
require "fileutils"

require_relative "systems"

BASE_URL = "https://myrient.erista.me/files/"
TOP_LEVEL_FOLDERS = [
  "No-Intro/",
  "Redump/"
]
IGNORED_FOLDERS = [
  "Parent directory",
  ".",
  ".."
]

def start_scraper
  create_root_contents
  scrape_top_level_folders
end

def scrape_top_level_folders
  TOP_LEVEL_FOLDERS.each do |folder|
    top_level_folder = get_folder(folder)
    top_level_folder_name = folder.split("/").first.downcase
    systems = parse_folder_contents_from_document(folder, top_level_folder, extra_for_next: "#{top_level_folder_name}/")

    systems.each do |system|
      next unless system[:is_folder]
      system_shortname = get_shortname_for_system(system)
      system[:system_shortname] = system_shortname

      contents = get_folder(system[:myrient_href])
      games = parse_folder_contents_from_document(system[:myrient_href], contents, system_shortname:)
      write_to_data_directory(JSON.generate(games), system[:next])
    end

    # Do this last so system shortname is included
    write_to_data_directory(JSON.generate(systems), "#{top_level_folder_name}.json")
  end
end

def get_folder(folder)
  uri = URI("#{BASE_URL}#{folder}")
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true

  request = Net::HTTP::Get.new uri

  response = https.request(request)
  handle_response(response) if response.is_a?(Net::HTTPOK)
end

def handle_response(response)
  Nokogiri::HTML(response.body)
end

def parse_folder_contents_from_document(previous_folders, document, extra_for_next: "", system_shortname: nil)
  document.css("td.link>a").filter_map do |folder|
    name = folder.text.strip.sub("/", "")
    myrient_href = folder["href"]
    is_folder = myrient_href.end_with?("/")
    next if IGNORED_FOLDERS.include?(name)

    {
      name:,
      myrient_href: "#{previous_folders}#{myrient_href}",
      is_folder:,
      next: is_folder ? "#{extra_for_next}#{sanitize_filename(name)}.json" : nil,
      system_shortname:
    }
  end
end

def write_to_data_directory(contents, file_name)
  destination = "data/#{file_name}"
  create_directory_if_needed(destination)
  puts "Writing to #{destination}"
  File.open(destination, "w") do |file|
    file.write(contents)
  end
end

def create_directory_if_needed(destination)
  folder_without_file_name = parse_destination_without_filename(destination)
  if folder_without_file_name && folder_without_file_name.strip != "" && !File.directory?(folder_without_file_name)
    puts "Creating directory #{folder_without_file_name}"
    FileUtils.mkdir_p(folder_without_file_name)
  end
end

def create_root_contents
  root_contents = TOP_LEVEL_FOLDERS.map do |folder|
    name = folder.split("/").first
    {name:, myrient_href: folder, is_folder: true, next: "#{name.downcase}.json"}
  end
  write_to_data_directory(JSON.generate(root_contents), "root.json")
end

def sanitize_filename(string) = string.downcase.gsub(/[^a-z0-9\-]+/i, "_")

def parse_destination_without_filename(destination)
  parts = destination.split("/")
  parts.pop
  parts.join("/")
end

def get_shortname_for_system(system)
  KNOWN_SYSTEMS.each do |known_system|
    if known_system[:regex].match(system[:name])
      return known_system[:shortname]
    end
  end
  nil
end

start_scraper
