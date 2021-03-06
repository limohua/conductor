#
#   Copyright 2011 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

=begin
XML Wrapper objects for the deployable XML format
=end

class ValidationError < RuntimeError; end

class ParameterXML
  def initialize(node)
    @root = node
  end

  def name
    @root['name']
  end

  def type
    @root['type']
  end

  def value
    value_node.content if value_node
  end

  def value=(value)
  end

  def reference?
    not reference_node.nil?
  end

  def reference_assembly
    reference_node['assembly'] if reference?
  end

  def reference_parameter
    reference_node['parameter'] if reference?
  end

  private
  def reference_node
    @reference ||= @root.at_xpath("./reference")
  end

  def value_node
    @value_node ||= @root.at_xpath("./value")
  end

  def value_node=(value)
    @root.content = "<value><![CDATA[#{value}]]></value>"
  end

end

class ServiceXML
  def initialize(name, description, executable, files, parameters)
    @name = name
    @description = description
    @executable = executable
    @files = files || []
    @parameter_nodes = parameters || []
  end
  attr_reader :name, :description, :executable, :files

  def parameters
    @parameters ||= @parameter_nodes.collect do |param_node|
      ParameterXML.new(param_node)
    end
  end
end

class AssemblyXML

  def initialize(xmlstr_or_node = "")
    if xmlstr_or_node.is_a? Nokogiri::XML::Node
      @root = xmlstr_or_node
    else
      doc = Nokogiri::XML(xmlstr_or_node)
      @root = doc.at_xpath("./assembly") if doc.root
    end
  end

  def validate!
    errors = []
    #errors << "image with uuid #{image_id} not found" unless Image.find(image_id)
    #if image_build
      #errors << "build with uuid #{image_build} not found" unless ImageBuild.find(image_build)
    #end
    raise ValidationError, errors.join(", ") unless errors.empty?
  end

  def image
    @image ||= @root.at("image")
  end

  def image_id
    @image_id ||= image['id']
  end

  def name
    @name ||= @root['name']
  end

  def hwp
    @hwp ||= @root['hwp']
  end

  def image_build
    @image_build ||= image['build']
  end

  def services
    # services and top-level tooling are mutually exclusive
    @services ||= collect_services || []
  end

  def to_s
    @root.to_s
  end

  def output_parameters
    @output_parameters ||=
      @root.xpath('returns/return').collect do |output_param|
      output_param['name']
    end
  end

  def requires_config_server?
    not (services.empty? and output_parameters.empty?)
  end

  def to_s
    @root.to_s
  end

  private
  def collect_services
    # collect the service level tooling
    nil_if_empty(@root.xpath("./services/service").collect do |service|
      name = service['name']
      description = service.at_xpath('./description')
      exe = service.at_xpath("./executable")
      files = service.xpath("./files/file")
      parameters = service.xpath("./parameters/parameter")
      ServiceXML.new(name, (description and description.text), exe, files, parameters)
    end)
  end

  def nil_if_empty(array)
    array unless array.nil? or array.empty?
  end
end


class DeployableXML

  DEPLOYABLE_VERSION = "1.0"
  def self.version
    DEPLOYABLE_VERSION
  end

  def initialize(xmlstr_or_node = "")
    if xmlstr_or_node.is_a? Nokogiri::XML::Node
      @root = xmlstr_or_node
    elsif xmlstr_or_node.is_a? String
      @doc = Nokogiri::XML(xmlstr_or_node) { |config| config.strict }
      @root = @doc.root.at_xpath("/deployable") if @doc.root
    end
    @relax_file = "#{File.dirname(File.expand_path(__FILE__))}/deployable-rng.xml"
  end

  def name
    @root["name"] if @root
  end

  def description
    node = @root ? @root.at_xpath("description") : nil
    node ? node.text : nil
  end

  def validate!
    # load the relaxNG file and validate
    return false if @root.nil?
    errors = relax.validate(@root.document) || []
    # ...and validate the assembly
    assemblies.each do |assembly|
      begin
        assembly.validate!
      rescue ValidationError => e
        errors << e.message
      end
    end
    errors.empty?
  end

  def assemblies
    @assemblies ||=
      @root.xpath('/deployable/assemblies/assembly').collect do |assembly_node|
      AssemblyXML.new(assembly_node)
    end
  end

  def image_uuids
    @image_uuids ||= @root.xpath('/deployable/assemblies/assembly/image').collect{|x| x['id']}
  end

  def set_parameter_value(assembly, service, parameter, value)
    # Why not do this in the ParameterXML class?
    # B/c we need to alter the deployable XML document and not the copy at the
    # ParameterXML object
    xpath = "//assembly[@name='#{assembly}']//service[@name='#{service}']//parameter[@name='#{parameter}']"
    param = @root.at_xpath(xpath)
    param.inner_html = "<value><![CDATA[#{value}]]></value>" if param
    @assemblies = nil # reset assemblies
  end

  def requires_config_server?
    assemblies.any? {|assembly| assembly.requires_config_server? }
  end

  def to_s
    @root.to_s
  end

  def self.import_xml_from_url(url)
    # Right now we allow this to raise exceptions on timeout / errors
    resource = RestClient::Resource.new(url, :open_timeout => 10, :timeout => 45)
    response = resource.get
    if response.code == 200
      response
    else
      false
    end
  end

  private
  def relax
    @relax ||= File.open(@relax_file) {|f| Nokogiri::XML::RelaxNG(f)}
  end
end
